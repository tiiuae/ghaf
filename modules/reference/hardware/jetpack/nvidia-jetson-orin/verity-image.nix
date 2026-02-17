# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds ESP and LVM partition images for A/B verity boot on Jetson Orin.
#
# ESP image: 512M vfat with systemd-boot (BOOTAA64.efi) + initial UKI
#            (with real dm-verity roothash baked in).
# LVM image: PV containing volume group "pool" with:
#   - root_<ver>_<hash>  (erofs nix-store image from ghafImage)
#   - verity_<ver>_<hash> (dm-verity hash tree from ghafImage)
#   - root_empty / verity_empty (inactive B slot, zeroed)
#   - swap (4G)
#   - persist (256M, expanded on first boot by btrfs-postboot)
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity-volume;

  # The ghafImage derivation from verity-volume.nix produces:
  #   ghaf_root_<ver>_<hash>.raw.zst   — erofs nix-store image (compressed)
  #   ghaf_verity_<ver>_<hash>.raw.zst — dm-verity hash tree (compressed)
  #   ghaf_kernel_<ver>_<hash>.efi     — UKI with real roothash
  #   ghaf_<ver>_<hash>.manifest       — JSON manifest
  inherit (config.system.build) ghafImage;

  # Fixed partition sizes in MiB — root and verity slots are computed at
  # build time from the actual image sizes (+ headroom).
  swapSizeMiB = 4096; # 4G swap
  persistSizeMiB = 256; # minimal, expanded on first boot by btrfs-postboot

  # ESP image: simple mkfs.vfat + mcopy, no VM needed.
  # Uses the UKI from ghafImage (which has the real roothash patched in),
  # not the raw UKI from system.build.uki (which still has the placeholder).
  espImage =
    pkgs.runCommand "esp-image"
      {
        nativeBuildInputs = with pkgs.buildPackages; [
          dosfstools
          mtools
          zstd
        ];
      }
      ''
        mkdir -p $out

        # Find the UKI from ghafImage (the one with real roothash)
        uki=$(find ${ghafImage} -name '*.efi' | head -1)
        if [ -z "$uki" ]; then
          echo "ERROR: No UKI (.efi) found in ghafImage output"
          ls -la ${ghafImage}/
          exit 1
        fi
        echo "Using UKI: $uki"

        # Create 512M FAT32 image
        truncate -s 512M esp.img
        mkfs.vfat -F 32 -n ESP esp.img

        # Install systemd-boot as BOOTAA64.efi
        # Use the system systemd package (not systemdMinimal, which may lack boot EFI files)
        boot_efi="${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi"
        mmd -i esp.img ::EFI
        mmd -i esp.img ::EFI/BOOT
        mmd -i esp.img ::EFI/Linux
        mcopy -i esp.img "$boot_efi" ::EFI/BOOT/BOOTAA64.efi

        # Install the UKI with real roothash
        mcopy -i esp.img "$uki" "::EFI/Linux/$(basename "$uki")"

        zstd --compress esp.img -o $out/esp.img.zst
      '';

  # LVM image: must be built in a VM because LVM needs block devices.
  # Reads the manifest from ghafImage to determine LV names, then writes
  # the erofs and verity raw data directly into correctly-named LVs.
  #
  # Use pkgsBuildBuild (native build platform) for the VM tools.
  # The VM runs on the build host and only writes raw data into LVs.
  buildPkgs = pkgs.pkgsBuildBuild;

  # LVM config for the VM — disable udev integration since the minimal
  # VM has no udev daemon; LVM will create device nodes directly.
  lvmConf = buildPkgs.writeText "lvm.conf" ''
    devices {
      dir = "/dev"
      scan = [ "/dev" ]
    }
    activation {
      udev_sync = 0
      udev_rules = 0
    }
  '';

  vmTools = buildPkgs.vmTools.override {
    rootModules = [
      "virtiofs"
      "virtio_pci"
      "virtio_blk"
      "virtio_balloon"
      "virtio_rng"
      "dm_mod" # LVM needs device-mapper
    ];
  };
  lvmImage = vmTools.runInLinuxVM (
    buildPkgs.stdenvNoCC.mkDerivation {
      name = "lvm-image";

      # runInLinuxVM uses overrideDerivation + stage2Init which doesn't
      # support structuredAttrs (origArgs becomes a flat string instead
      # of a bash array, causing the builder invocation to fail silently)
      __structuredAttrs = false;

      buildInputs = with buildPkgs; [
        lvm2
        util-linux
        btrfs-progs
        zstd
        jq
      ];

      memSize = 4096; # 4G RAM for the VM

      preVM = ''
        set -efx
        mkdir -p $out

        # Compute slot sizes from actual images (+ headroom)
        manifest=$(find ${ghafImage} -name '*.manifest' | head -1)
        root_file=$(${buildPkgs.jq}/bin/jq -r '.root.file' "$manifest")
        verity_file=$(${buildPkgs.jq}/bin/jq -r '.verity.file' "$manifest")

        # Get uncompressed sizes in bytes from zstd verbose listing
        # Output line: "Decompressed Size: 9.37 GiB (10058227712 B)"
        get_decompressed_size() {
          ${buildPkgs.zstd}/bin/zstd --list -v "$1" 2>/dev/null \
            | awk '/Decompressed Size/ { match($0, /\(([0-9]+) B\)/, m); print m[1] }'
        }

        root_bytes=$(get_decompressed_size "${ghafImage}/$root_file")
        verity_bytes=$(get_decompressed_size "${ghafImage}/$verity_file")

        # Round up to MiB + headroom
        root_mib=$(( (root_bytes + 1048575) / 1048576 + 512 ))
        verity_mib=$(( (verity_bytes + 1048575) / 1048576 + 16 ))
        echo "Root image: $root_bytes bytes -> LV size: $root_mib MiB"
        echo "Verity image: $verity_bytes bytes -> LV size: $verity_mib MiB"

        # Total LVM PV: 2x root + 2x verity + swap + persist + 64M overhead
        lvm_mib=$(( 2 * root_mib + 2 * verity_mib + ${toString swapSizeMiB} + ${toString persistSizeMiB} + 64 ))
        echo "LVM PV size: $lvm_mib MiB"

        ${buildPkgs.qemu}/bin/qemu-img create -f raw "$out/system.img" ''${lvm_mib}M

        # Pass computed sizes to buildCommand via xchg
        mkdir -p xchg
        echo "$root_mib" > xchg/root_size_mib
        echo "$verity_mib" > xchg/verity_size_mib
      '';

      QEMU_OPTS = ''-drive file="$out"/system.img,if=virtio,cache=unsafe,werror=report,format=raw'';

      # postVM runs on the build host after the VM exits.
      # Convert raw → NVIDIA sparse format, then compress with zstd.
      # tegradevflash unsparsifies on the fly, skipping zero-filled blocks —
      # this cuts flash time dramatically for mostly-empty images.
      postVM = ''
        # Save raw image size (needed for GPT partition table in flash.xml)
        ${buildPkgs.coreutils}/bin/stat -c%s "$out/system.img" > "$out/system.raw_size"
        # Using NVIDIA's mksparse (not img2simg) for format compatibility.
        ${pkgs.nvidia-jetpack.bspSrc}/bootloader/mksparse --fillpattern=0 "$out/system.img" "$out/system.simg"
        rm "$out/system.img"
        ${buildPkgs.zstd}/bin/zstd --compress --rm "$out/system.simg" -o "$out/system.img.zst"
      '';

      buildCommand = ''
        # Configure LVM to create device nodes directly (no udev in this VM)
        export LVM_SYSTEM_DIR=/tmp/lvm
        mkdir -p /tmp/lvm
        cp ${lvmConf} /tmp/lvm/lvm.conf

        LVM_DEV=/dev/vda

        # Parse the manifest to get LV names
        manifest=$(find ${ghafImage} -name '*.manifest' | head -1)
        if [ -z "$manifest" ]; then
          echo "ERROR: No manifest found in ghafImage output"
          ls -la ${ghafImage}/
          exit 1
        fi
        echo "Using manifest: $manifest"

        # Extract the root and verity filenames (which encode version+hash)
        root_file=$(jq -r '.root.file' "$manifest")
        verity_file=$(jq -r '.verity.file' "$manifest")
        echo "Root file: $root_file"
        echo "Verity file: $verity_file"

        # Extract LV name suffix from filename: ghaf_root_<ver>_<hash>.raw.zst -> <ver>_<hash>
        # Pattern: ghaf_root_VERSION_HASH.raw.zst
        lv_suffix=$(echo "$root_file" | sed 's/^ghaf_root_//; s/\.raw\.zst$//')
        echo "LV suffix: $lv_suffix"

        # Create LVM PV and VG on the raw disk
        pvcreate "$LVM_DEV"
        vgcreate pool "$LVM_DEV"

        # Read slot sizes computed by preVM from actual images
        root_mib=$(cat /tmp/xchg/root_size_mib)
        verity_mib=$(cat /tmp/xchg/verity_size_mib)
        echo "Root slot size: $root_mib MiB, Verity slot size: $verity_mib MiB"

        # Create logical volumes with correct names for the veritysetup generator
        lvcreate -L "''${root_mib}M"   -n "root_$lv_suffix"   pool
        lvcreate -L "''${verity_mib}M" -n "verity_$lv_suffix" pool
        lvcreate -L "''${root_mib}M"   -n root_empty          pool
        lvcreate -L "''${verity_mib}M" -n verity_empty        pool
        lvcreate -L ${toString swapSizeMiB}M    -n swap        pool
        lvcreate -L ${toString persistSizeMiB}M -n persist     pool

        # Decompress and write erofs image into root LV
        echo "Writing erofs image to root_$lv_suffix..."
        zstd -d "${ghafImage}/$root_file" --stdout | dd of="/dev/pool/root_$lv_suffix" bs=4M conv=notrunc status=progress

        # Decompress and write verity hash tree into verity LV
        echo "Writing verity data to verity_$lv_suffix..."
        zstd -d "${ghafImage}/$verity_file" --stdout | dd of="/dev/pool/verity_$lv_suffix" bs=4M conv=notrunc status=progress

        # Format swap
        mkswap -L swap /dev/pool/swap

        # Format persist with btrfs
        mkfs.btrfs -L persist /dev/pool/persist

        # Deactivate VG before finishing
        vgchange -an pool
      '';
    }
  );
in
{
  config = lib.mkIf cfg.enable {
    system.build.verityImages = pkgs.runCommand "verity-images" { } ''
      mkdir -p $out
      ln -s ${espImage}/esp.img.zst $out/esp.img.zst
      ln -s ${lvmImage}/system.img.zst $out/system.img.zst
      ln -s ${lvmImage}/system.raw_size $out/system.raw_size
    '';

    # Override formatAttr so the orin target builder picks up verityImages
    # instead of sdImage. The option is defined by nixos-generators' format-module.nix
    # which the verity target includes solely for this purpose.
    formatAttr = lib.mkForce "verityImages";

    # Configure filesystem mounts for the verity layout
    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
      "/persist" = {
        device = "/dev/pool/persist";
        fsType = "btrfs";
        neededForBoot = true;
      };
    };

    swapDevices = [
      {
        device = "/dev/pool/swap";
      }
    ];

    # Disable systemd-boot-dtb (Type 1 entries not used with UKI)
    ghaf.hardware.aarch64.systemd-boot-dtb.enable = lib.mkForce false;

    # Disable regular systemd-boot (UKI autodiscovery is used instead)
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  };
}
