# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds ESP and LVM partition images for A/B verity boot on Jetson Orin.
#
# ESP image: 512M vfat with systemd-boot + UKI (without .dtb section).
#            The UKI omits the .dtb because NVIDIA's EFI_DT_FIXUP_PROTOCOL
#            corrupts DTBs loaded from memory by sd-stub. Without .dtb,
#            sd-stub skips fixup and the kernel uses the firmware's DTB
#            already in the EFI Configuration Table (installed by DtPlatformDxe).
#
# LVM image: PV containing volume group "pool" with only the A-slot:
#   - root_<ver>_<hash>  (erofs nix-store image from ghafImage)
#   - verity_<ver>_<hash> (dm-verity hash tree from ghafImage)
#
# Swap, persist and B-slot LVs are created on first boot by
# firstboot-persist.nix, which resizes the APP partition to fill the
# eMMC and uses the free VG space.
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

  # The ESP FAT image is built at flash time (not here) so that
  # EFI binaries can be signed with a private key that never enters
  # the Nix store.  We only export the individual files needed.
  espFiles = pkgs.runCommand "esp-files" { } ''
    mkdir -p $out

    # UKI (roothash-patched)
    uki=$(find ${ghafImage} -name '*.efi' | head -1)
    if [ -z "$uki" ]; then
      echo "ERROR: No UKI (.efi) found in ghafImage output"
      ls -la ${ghafImage}/
      exit 1
    fi
    ln -s "$uki" "$out/uki.efi"
    basename "$uki" > "$out/uki-filename"

    # systemd-boot
    ln -s "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi" \
      "$out/systemd-bootaa64.efi"
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

        # Only A-slot: root + verity + 64M LVM metadata overhead.
        # B-slot, swap and persist are created on first boot by
        # firstboot-persist.nix after the APP partition is resized.
        lvm_mib=$(( root_mib + verity_mib + 64 ))
        echo "LVM PV size: $lvm_mib MiB"

        ${buildPkgs.qemu}/bin/qemu-img create -f raw "$out/system.img" ''${lvm_mib}M

        # Pass computed sizes to buildCommand via xchg
        mkdir -p xchg
        echo "$root_mib" > xchg/root_size_mib
        echo "$verity_mib" > xchg/verity_size_mib
      '';

      QEMU_OPTS = ''-drive file="$out"/system.img,if=virtio,cache=unsafe,werror=report,format=raw'';

      # postVM runs on the build host after the VM exits.
      # The image is small (only A-slot, ~5.5 GiB) so we just
      # zstd-compress the raw image directly — no sparse conversion needed.
      postVM = ''
        ${buildPkgs.coreutils}/bin/stat -c%s "$out/system.img" > "$out/system.raw_size"
        ${buildPkgs.zstd}/bin/zstd --compress --rm "$out/system.img" -o "$out/system.img.zst"
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

        # Create A-slot logical volumes only. B-slot, swap and persist
        # are created on first boot by firstboot-persist.nix.
        lvcreate -L "''${root_mib}M"   -n "root_$lv_suffix"   pool
        lvcreate -L "''${verity_mib}M" -n "verity_$lv_suffix" pool

        # Decompress and write erofs image into root LV
        echo "Writing erofs image to root_$lv_suffix..."
        zstd -d "${ghafImage}/$root_file" --stdout | dd of="/dev/pool/root_$lv_suffix" bs=4M conv=notrunc status=progress

        # Decompress and write verity hash tree into verity LV
        echo "Writing verity data to verity_$lv_suffix..."
        zstd -d "${ghafImage}/$verity_file" --stdout | dd of="/dev/pool/verity_$lv_suffix" bs=4M conv=notrunc status=progress

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
      ln -s ${espFiles} $out/esp-files
      ln -s ${lvmImage}/system.img.zst $out/system.img.zst
      ln -s ${lvmImage}/system.raw_size $out/system.raw_size
    '';

    # Configure filesystem mounts for the verity layout.
    # /persist and swap are declared in firstboot-persist.nix.
    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
    };

    # Disable systemd-boot-dtb and NixOS boot installer — ESP is built at image time.
    ghaf.hardware.aarch64.systemd-boot-dtb.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

    # Build UKI WITHOUT .dtb section. NVIDIA's EFI_DT_FIXUP_PROTOCOL corrupts
    # DTBs loaded from memory by sd-stub. Without .dtb, sd-stub skips fixup
    # and the kernel uses the firmware's DTB from the EFI Configuration Table
    # (installed by DtPlatformDxe during UEFI boot).
    #
    # NixOS adds DeviceTree to boot.uki.settings.UKI when
    # hardware.deviceTree is enabled. We can't disable hardware.deviceTree
    # (the flash tooling needs it for DTB overlays), so we override the
    # entire UKI section to omit DeviceTree while keeping all other
    # settings at their NixOS defaults.
    boot.uki.settings.UKI = lib.mkForce {
      Linux = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
      Initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      Cmdline = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
      Stub = "${pkgs.systemd}/lib/systemd/boot/efi/linux${pkgs.stdenv.hostPlatform.efiArch}.efi.stub";
      Uname = config.boot.kernelPackages.kernel.modDirVersion;
      OSRelease = "@${config.system.build.etc}/etc/os-release";
      EFIArch = pkgs.stdenv.hostPlatform.efiArch;
    };
  };
}
