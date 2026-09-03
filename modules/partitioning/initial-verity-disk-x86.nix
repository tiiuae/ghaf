# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# x86 bootstrap disk for the shared secure A/B payload. The image is emitted
# unsigned; ghaf-sign-x86-image signs the ESP later, outside the Nix store.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity.initialDisk;
  verityCfg = config.ghaf.partitioning.verity;
  diskoCfg = config.ghaf.partitioning.disko;
  # ESP plus two fixed root/verity pairs, swap, persist, and conservative
  # headroom for GPT, LUKS, and LVM metadata.
  minimumImageSizeMiB =
    500
    + 2 * verityCfg.rootSlotSizeMiB
    + 2 * verityCfg.veritySlotSizeMiB
    + diskoCfg.swapSize
    + diskoCfg.persistSize
    + 4 * 1024;
  updateImage = config.system.build.ghafUpdateImage;
  verityLvmImage = config.system.build.verityLvmImage;
  trustInventory = pkgs.writeText "ghaf-secure-ab-public-trust.json" (
    builtins.toJSON {
      external = config.ghaf.secureUpdate.externalPublicTrustConfigured;
      inherit (config.ghaf.secureUpdate) target generation publicTrustDigests;
    }
  );
  buildPkgs = pkgs.pkgsBuildBuild;
  vmTools = buildPkgs.vmTools.override {
    rootModules = [
      "virtiofs"
      "virtio_pci"
      "virtio_blk"
      "virtio_balloon"
      "virtio_rng"
      "dm_mod"
      "dm_crypt"
    ];
  };

  image = vmTools.runInLinuxVM (
    buildPkgs.stdenvNoCC.mkDerivation {
      name = "ghaf-initial-verity-x86-disk";
      __structuredAttrs = false;
      buildInputs = with buildPkgs; [
        bmaptool
        btrfs-progs
        coreutils
        cryptsetup
        dosfstools
        gawk
        gptfdisk
        jq
        lvm2
        parted
        systemd
        util-linux
        zstd
      ];
      memSize = 4096;

      preVM = ''
        set -efx
        mkdir -p "$out"
        ${buildPkgs.qemu}/bin/qemu-img create -f raw "$out/ghaf-image.raw" ${toString diskoCfg.imageSize}M
      '';
      QEMU_OPTS = ''-drive file="$out"/ghaf-image.raw,if=virtio,cache=unsafe,werror=report,format=raw'';
      postVM = ''
        bmaptool create "$out/ghaf-image.raw" -o "$out/ghaf-image.bmap"
        cores="''${NIX_BUILD_CORES:-1}"
        if [ "$cores" -gt 8 ]; then cores=8; fi
        zstd -T"$cores" --compress "$out/ghaf-image.raw" -o "$out/ghaf-image.raw.zst" --rm
        install -m 0644 ${trustInventory} "$out/public-trust.json"
      '';

      buildCommand = ''
        set -efx
        disk=/dev/vda
        sgdisk --zap-all "$disk"
        sgdisk --new=1:1MiB:+500MiB --typecode=1:ef00 --change-name=1:ESP "$disk"
        sgdisk --new=2:0:0 --typecode=2:8e00 --change-name=2:disk-disk1-luks "$disk"
        partprobe "$disk"
        udevadm settle

        mkfs.vfat -F 32 -n ESP /dev/vda1
        mkdir -p /mnt/esp/EFI/systemd /mnt/esp/EFI/BOOT /mnt/esp/EFI/Linux /mnt/esp/loader
        mount /dev/vda1 /mnt/esp
        mkdir -p /mnt/esp/EFI/systemd /mnt/esp/EFI/BOOT /mnt/esp/EFI/Linux /mnt/esp/loader
        install -m 0644 ${config.systemd.package}/lib/systemd/boot/efi/systemd-bootx64.efi \
          /mnt/esp/EFI/systemd/systemd-bootx64.efi
        install -m 0644 ${config.systemd.package}/lib/systemd/boot/efi/systemd-bootx64.efi \
          /mnt/esp/EFI/BOOT/BOOTX64.EFI

        manifest=$(find ${updateImage} -name '*.manifest' -print -quit)
        uki=$(find ${updateImage} -name '*.efi' -print -quit)
        version=$(jq -er '.version' "$manifest")
        root_hash=$(jq -er '.root_verity_hash' "$manifest")
        uki_name="ghaf-$version-''${root_hash:0:16}.efi"
        install -m 0644 "$uki" "/mnt/esp/EFI/Linux/$uki_name"
        printf 'timeout %s\ndefault %s\neditor no\n' \
          ${
            lib.escapeShellArg (
              if config.boot.loader.timeout == null then "menu-force" else toString config.boot.loader.timeout
            )
          } \
          "''${uki_name%.efi}" > /mnt/esp/loader/loader.conf
        sync -f /mnt/esp
        umount /mnt/esp

        # The one-time empty development passphrase matches Ghaf's existing
        # non-interactive x86 enrollment flow. First boot enrolls TPM/FIDO2 and
        # a recovery key, then removes this password slot.
        printf '\n' | cryptsetup luksFormat --batch-mode --type luks2 "$disk"2
        printf '\n' | cryptsetup open "$disk"2 crypted
        zstd -d ${verityLvmImage}/system.img.zst --stdout \
          | dd of=/dev/mapper/crypted bs=4M conv=notrunc status=progress
        pvresize /dev/mapper/crypted
        vgchange -ay pool

        root_mib=$(cat ${verityLvmImage}/root_size_mib)
        verity_mib=$(cat ${verityLvmImage}/verity_size_mib)
        DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n root_empty -L "''${root_mib}M" pool
        DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n verity_empty -L "''${verity_mib}M" pool
        DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n swap -L ${toString diskoCfg.swapSize}M pool
        DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n persist -L ${toString diskoCfg.persistSize}M pool
        vgmknodes pool
        mkswap -L swap /dev/pool/swap
        mkfs.btrfs -L persist /dev/pool/persist
        vgchange -an pool
        cryptsetup close crypted
      '';
    }
  );
in
{
  options.ghaf.partitioning.verity.initialDisk.enable =
    lib.mkEnableOption "an initial x86 GPT/LUKS/LVM secure A/B disk image";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixpkgs.hostPlatform.system == "x86_64-linux";
        message = "ghaf.partitioning.verity.initialDisk is currently implemented only for x86_64-linux";
      }
      {
        assertion = config.ghaf.partitioning.verity.enable;
        message = "ghaf.partitioning.verity.initialDisk requires the verity update layout";
      }
      {
        assertion = config.ghaf.storage.encryption.enable && !config.ghaf.storage.encryption.deferred;
        message = "ghaf.partitioning.verity.initialDisk requires immediate LUKS configuration";
      }
      {
        assertion = diskoCfg.imageSize >= minimumImageSizeMiB;
        message = "secure A/B imageSize is ${toString diskoCfg.imageSize} MiB but two fixed system slots and persistent volumes require at least ${toString minimumImageSizeMiB} MiB";
      }
    ];

    ghaf.partitioning.disko.imageSize = lib.mkDefault minimumImageSizeMiB;

    fileSystems."/boot" = lib.mkForce {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };

    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    system.build.ghafImage = lib.mkForce image;
  };
}
