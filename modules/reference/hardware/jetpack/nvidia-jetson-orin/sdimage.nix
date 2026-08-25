# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which configures sd-image to generate images to be used with NVIDIA
# Jetson Orin AGX/NX devices. Supposed to be imported from format-module.nix.
#
# Generates ESP partition contents mimicking systemd-boot installation. Can be
# used to generate both images to be used in flashing script, and image to be
# flashed to external disk. NVIDIA's edk2 does not seem to care to much about
# the partition types, as long as there is a FAT partition, which contains
# EFI-directory and proper kind of structure, it finds the EFI-applications and
# boots them successfully.
#
# When ghaf.image.sdcard.uki.enable is set, the ESP is populated with a Unified
# Kernel Image (Type #2 BLS entry) instead of the traditional Type #1 entry
# produced by mk-esp-contents.py. The UKI bundles kernel, initrd, cmdline, DTB,
# and os-release into a single PE/COFF binary discovered automatically by
# systemd-boot from EFI/Linux/.
#
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}:
let
  # The flash-time LUKS conversion needs more headroom than the stock sd-image
  # builder leaves after its final resize2fs pass.
  rootfsExtraSlackMiB = 64;

  # Pin the LUKS2 header UUID so the runtime references (crypttab/udev/resize in
  # jetson-orin.nix) resolve the root by /dev/disk/by-uuid/<uuid> on both the USB
  # sd-image (MBR) and the eMMC/NVMe flash (GPT).
  inherit (config.ghaf.hardware.nvidia.orin.diskEncryption) luksUuid;

  cryptsetup =
    (pkgs.callPackage "${toString pkgs.path}/pkgs/by-name/cr/cryptsetup/package.nix" { }).overrideAttrs
      (oldAttrs: {
        # /run/cryptsetup (the upstream default) is not writable inside the
        # image build, and /build only exists on sandboxed-to-/build builders.
        # /tmp is writable in every nix build environment.
        configureFlags = oldAttrs.configureFlags ++ [
          "--with-luks2-lock-path=/tmp/cryptsetup"
        ];
      });

  cfg = config.ghaf.image.sdcard;
  inherit (pkgs.stdenv.hostPlatform) efiArch;
  fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
in
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];

  options.ghaf.image.sdcard.uki = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Populate the SD image ESP with a Unified Kernel Image (Type #2 BLS
        entry) instead of the traditional Type #1 entries from
        mk-esp-contents.py.

        The UKI bundles kernel, initrd, cmdline, DTB, and os-release into a
        single PE/COFF binary that systemd-boot discovers automatically from
        EFI/Linux/.

        Note: Enabling this produces an image without bootloader-level
        generation rollback. A single UKI is placed in the ESP.
      '';
    };

    dtbPadding = lib.mkOption {
      type = lib.types.int;
      default = 65536;
      description = ''
        Extra padding bytes added to the device tree blob.
        systemd-stub needs room in the FDT for runtime modifications
        (e.g. adding /chosen properties). Increase if firmware rejects
        the DTB with "Invalid header detected on UEFI supplied FDT".
      '';
    };
  };

  config = {
    boot.loader.grub.enable = false;
    hardware.enableAllHardware = lib.mkForce false;

    # Jetson-specific UKI build configuration
    boot.uki.settings = lib.mkIf cfg.uki.enable (
      let
        # When packed in a UKI, the dtb needs some padding to avoid error:
        # "Invalid header detected on UEFI supplied FDT"
        # The default value of 64K for dtbPadding should be more than enough.
        paddedDtb =
          pkgs.runCommand "padded-dtb"
            {
              nativeBuildInputs = [ pkgs.dtc ];
            }
            ''
              mkdir -p $out
              dtc -I dtb -O dtb -p ${toString cfg.uki.dtbPadding} -o $out/padded.dtb ${fdtPath}
            '';
      in
      {
        UKI = {
          DeviceTree = "${paddedDtb}/padded.dtb";
        };
      }
    );

    sdImage =
      let
        # TODO do we really need replaceVars just to set the python string in the
        # shbang?
        mkESPContentSource = pkgs.replaceVars ./mk-esp-contents.py {
          inherit (pkgs.buildPackages) python3;
        };
        mkESPContent =
          pkgs.runCommand "mk-esp-contents"
            {
              nativeBuildInputs = with pkgs; [
                mypy
                python3
              ];
            }
            ''
              install -m755 ${mkESPContentSource} $out
              mypy \
                --no-implicit-optional \
                --disallow-untyped-calls \
                --disallow-untyped-defs \
                $out
            '';
        # fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
      in
      {
        firmwareSize = if cfg.uki.enable then 512 else 256;

        # The initrd resize-partitions service grows the root partition and
        # filesystem for both the plain and the LUKS layout, so the stock
        # stage-2 expand-root-partition.service is redundant everywhere (and
        # broken for LUKS: it resolves the root device via `lsblk -npo PKNAME /`,
        # which is empty for a /dev/mapper/cryptroot root).
        expandOnBoot = false;
        populateFirmwareCommands =
          if cfg.uki.enable then
            ''
              mkdir -pv firmware/EFI/BOOT
              mkdir -pv firmware/EFI/Linux
              mkdir -pv firmware/loader

              # Install systemd-boot as the UEFI bootloader
              cp -v ${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi \
                    firmware/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI

              # Install the UKI (Type #2 entry). systemd-boot discovers it
              # automatically from EFI/Linux/
              cp -v ${config.system.build.uki}/${config.system.boot.loader.ukiFile} \
                    firmware/EFI/Linux/${config.system.boot.loader.ukiFile}

              # Jetson UEFI falls back to its shell when freshly erased
              # variables contain no boot entry. Launch the removable loader.
              printf '%s\r\n' '\EFI\BOOT\BOOT${lib.toUpper efiArch}.EFI' > firmware/startup.nsh

              # Minimal loader configuration
              cat > firmware/loader/loader.conf << EOF
              timeout 0
              editor no
              console-mode keep
              EOF
            ''
          else
            ''
              mkdir -pv firmware
              ${mkESPContent} \
                --toplevel ${config.system.build.toplevel} \
                --output firmware/ \
                --device-tree ${fdtPath}
            '';

        populateRootCommands = "";

        preBuildCommands = ''
          ${lib.optionalString config.ghaf.hardware.nvidia.orin.diskEncryption.enable ''
            printf "\nGeneric LUKS rootfs encryption is enabled.\n"

            ROOT_IMAGE=$root_fs

            if [ ! -w "$ROOT_IMAGE" ]; then
              chmod 755 $ROOT_IMAGE
            fi

            e2fsck -fy "$ROOT_IMAGE"

            # Reserve space for LUKS
            current_blocks=$(dumpe2fs -h "$ROOT_IMAGE" 2>/dev/null | sed -n 's/^Block count:[[:space:]]*//p')
            block_size=$(dumpe2fs -h "$ROOT_IMAGE" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
            extra_blocks=$(( ${toString rootfsExtraSlackMiB} * 1024 * 1024 / block_size ))
            resize2fs "$ROOT_IMAGE" "$((current_blocks + extra_blocks))"

            LUKS_REDUCTION_BYTES=$((16 * 1024 * 1024))
            LUKS_DATA_OFFSET_BYTES=$((8 * 1024 * 1024))
            # Host-side verification of root.enc.img shows the mapped device ends up
            # four additional LUKS data offsets smaller than the final image file.
            # Account for that before reencrypting so the ext4 filesystem fits the
            # post-conversion payload exactly.
            LUKS_PAYLOAD_SLACK_BYTES=$((4 * LUKS_DATA_OFFSET_BYTES))

            GHAF_LUKS_PASSPHRASE_FILE=$(mktemp ".luks-passphrase.XXXXXX")
            chmod 600 "$GHAF_LUKS_PASSPHRASE_FILE"
            printf '%s' "${
              if config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable then
                config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.deviceManufacturerPassphrase
              else
                config.ghaf.hardware.nvidia.orin.diskEncryption.userPassphrase.passphrase
            }" > "$GHAF_LUKS_PASSPHRASE_FILE"

            echo "Shrinking plaintext root filesystem before LUKS conversion ..."
            e2fsck -fy "$ROOT_IMAGE"
            BLOCK_SIZE=$(dumpe2fs -h "$ROOT_IMAGE" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
            TARGET_PAYLOAD_BYTES=$(( $(stat -c %s "$ROOT_IMAGE") - LUKS_REDUCTION_BYTES - LUKS_DATA_OFFSET_BYTES - LUKS_PAYLOAD_SLACK_BYTES ))
            TARGET_BLOCKS=$(( TARGET_PAYLOAD_BYTES / BLOCK_SIZE ))
            resize2fs "$ROOT_IMAGE" "$TARGET_BLOCKS"
            # Keep the plaintext file one LUKS data offset larger than the
            # ext4 payload so reencrypt does not collapse the final image size
            # together with the resized filesystem.
            truncate -s "$(( TARGET_PAYLOAD_BYTES + LUKS_DATA_OFFSET_BYTES ))" "$ROOT_IMAGE"

            echo "Encrypting extracted root image with LUKS2 ..."
            # cryptsetup is built with --with-luks2-lock-path=/tmp/cryptsetup;
            # newer releases refuse to take the reencryption lock if that
            # directory does not already exist.
            mkdir -p /tmp/cryptsetup
            ${cryptsetup}/bin/cryptsetup reencrypt \
              --encrypt \
              --type luks2 \
              --batch-mode \
              --uuid "${luksUuid}" \
              --reduce-device-size "$LUKS_REDUCTION_BYTES" \
              --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
              "$ROOT_IMAGE"

            # Re-materialize the final APP image as a fully allocated raw file.
            # The flash pipeline should see a dense payload, not a sparse file
            # with holes introduced by truncate during the sizing step above.
            ROOT_IMAGE_DENSE_PATH="root.enc.dense.img"
            cp --sparse=never "$ROOT_IMAGE" "$ROOT_IMAGE_DENSE_PATH"
            mv "$ROOT_IMAGE_DENSE_PATH" "$ROOT_IMAGE"

            rm -f "$GHAF_LUKS_PASSPHRASE_FILE"
          ''}
        '';
        postBuildCommands = ''
          fdisk_output=$(fdisk -l "$img")

          # Offsets and sizes are in 512 byte sectors
          blocksize=512

          # ESP partition offset and sector count
          part_esp=$(echo -n "$fdisk_output" | tail -n 2 | head -n 1 | tr -s ' ')
          part_esp_begin=$(echo -n "$part_esp" | cut -d ' ' -f2)
          part_esp_count=$(echo -n "$part_esp" | cut -d ' ' -f4)

          # root-partition offset and sector count
          part_root=$(echo -n "$fdisk_output" | tail -n 1 | head -n 1 | tr -s ' ')
          part_root_begin=$(echo -n "$part_root" | cut -d ' ' -f3)
          part_root_count=$(echo -n "$part_root" | cut -d ' ' -f4)

          echo -n $part_esp_begin > $out/esp.offset
          echo -n $part_esp_count > $out/esp.size
          echo -n $part_root_begin > $out/root.offset
          echo -n $part_root_count > $out/root.size
        '';
      };

    #TODO: should we use the default
    #https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/sd-card/sd-image.nix#L177
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
      fsType = "vfat";
    };

  };
}
