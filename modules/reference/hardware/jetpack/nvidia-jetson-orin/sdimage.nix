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

  cryptsetup =
    (pkgs.callPackage "${toString pkgs.path}/pkgs/by-name/cr/cryptsetup/package.nix" { }).overrideAttrs
      (oldAttrs: {
        configureFlags = oldAttrs.configureFlags ++ [
          "--with-luks2-lock-path=/build/cryptsetup"
        ];
      });
in
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];

  boot.loader.grub.enable = false;
  hardware.enableAllHardware = lib.mkForce false;

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
      fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
    in
    {
      firmwareSize = 256;
      populateFirmwareCommands = ''
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

            #
            if [ ! -w "$ROOT_IMAGE" ]; then
              chmod 755 $ROOT_IMAGE
            fi

            # Sanity check
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

            # cryptsetup read passphrase from file.
            GHAF_LUKS_PASSPHRASE_FILE=$(mktemp ".luks-passphrase.XXXXXX")
            chmod 600 "$GHAF_LUKS_PASSPHRASE_FILE"
            printf '%s' "${
              if config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable then
                config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.deviceManufacturePassphrase
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
            ${cryptsetup}/bin/cryptsetup reencrypt \
              --encrypt \
              --type luks2 \
              --batch-mode \
              --reduce-device-size "$LUKS_REDUCTION_BYTES" \
              --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
              "$ROOT_IMAGE"

            # Re-materialize the final APP image as a fully allocated raw file.
            # The flash pipeline should see a dense payload, not a sparse file
            # with holes introduced by truncate during the sizing step above.
            ROOT_IMAGE_DENSE_PATH="root.enc.dense.img"
            cp --sparse=never "$ROOT_IMAGE" "$ROOT_IMAGE_DENSE_PATH"
            mv "$ROOT_IMAGE_DENSE_PATH" "$ROOT_IMAGE"

            if [ "''${GHAF_LUKS_CHECK_GEOMETRY:-0}" = "1" ]; then
              echo "Checking encrypted root image geometry ..."
              ${cryptsetup}/bin/cryptsetup close ghaf-luks-verify 2>/dev/null || true
              GEOMETRY_LOOPDEV=$(losetup --find --show "$ROOT_IMAGE")
              ${cryptsetup}/bin/cryptsetup open \
                --readonly \
                --type luks \
                --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
                "$GEOMETRY_LOOPDEV" ghaf-luks-verify
              MAPPER_BYTES=$(blockdev --getsize64 /dev/mapper/ghaf-luks-verify)
              FS_BLOCK_COUNT=$(dumpe2fs -h /dev/mapper/ghaf-luks-verify 2>/dev/null | sed -n 's/^Block count:[[:space:]]*//p')
              FS_BLOCK_SIZE=$(dumpe2fs -h /dev/mapper/ghaf-luks-verify 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
              FS_BYTES=$(( FS_BLOCK_COUNT * FS_BLOCK_SIZE ))
              echo "Encrypted image bytes: $(stat -c %s "$ROOT_IMAGE")"
              echo "Mapped payload bytes: $MAPPER_BYTES"
              echo "Ext4 filesystem bytes: $FS_BYTES"
              if [ "$FS_BYTES" -ne "$MAPPER_BYTES" ]; then
                echo "ERROR: ext4 filesystem does not fit encrypted payload." >&2
                ${cryptsetup}/bin/cryptsetup close ghaf-luks-verify
                losetup -d "$GEOMETRY_LOOPDEV"
                exit 1
              fi
              ${cryptsetup}/bin/cryptsetup close ghaf-luks-verify
              losetup -d "$GEOMETRY_LOOPDEV"


            if [ "''${GHAF_LUKS_VALIDATE_IMAGE:-0}" = "1" ]; then
              echo "Validating encrypted root image ..."
              ${cryptsetup}/bin/cryptsetup close ghaf-luks-verify 2>/dev/null || true
              VALIDATE_LOOPDEV=$(losetup --find --show "$ROOT_IMAGE")
              ${cryptsetup}/bin/cryptsetup open \
                --type luks \
                --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
                "$VALIDATE_LOOPDEV" ghaf-luks-verify
              tune2fs -l /dev/mapper/ghaf-luks-verify >/dev/null
              if [ "''${GHAF_LUKS_VALIDATE_FULL_FSCK:-0}" = "1" ]; then
                echo "Running full fsck validation on encrypted root image ..."
                e2fsck -fn /dev/mapper/ghaf-luks-verify
              fi
              ${cryptsetup}/bin/cryptsetup close ghaf-luks-verify
              losetup -d "$VALIDATE_LOOPDEV"
            fi

            rm -f "$GHAF_LUKS_PASSPHRASE_FILE"
          fi
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
}
