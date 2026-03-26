# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which provides partition template for NVIDIA Jetson AGX Orin flash-script.
#
# This module configures legacyFlashScript to extract ESP and root partitions
# from the compressed sdImage at flash time, then patches the partition sizes
# into flash.xml before running NVIDIA's flash.sh.
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  inherit (pkgs.nvidia-jetpack) bspSrc;

  # sdImage containing ESP and root partitions (compressed)
  images = config.system.build.sdImage;

  # eMMC partition layout as structured Nix data.
  # Serialized to JSON and spliced into NVIDIA's flash XML by
  # splice-flash-xml.py, which replaces the <device type="sdmmc_user">
  # children. This avoids fragile line-count splicing.
  #
  # Partition sizes are injected at build time from the sdImage metadata
  # via --set (sectors * 512 → bytes).
  partitionsEmmc = [
    {
      name = "master_boot_record";
      type = "protective_master_boot_record";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "512";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
    {
      name = "primary_gpt";
      type = "primary_gpt";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "19968";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
    {
      name = "esp";
      type = "data";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0"; # overridden by --set from sdImage metadata at build time
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        percent_reserved = "0";
        filename = "bootloader/esp.img";
        partition_type_guid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
        description = "EFI system partition with systemd-boot.";
      };
    }
    {
      name = "APP";
      type = "data";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0"; # overridden by --set from sdImage metadata at build time
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        align_boundary = "16384";
        percent_reserved = "0x808";
        unique_guid = "APPUUID";
        filename = "root.img";
        description = "Contains the rootfs, placed at the end of the device as /dev/mmcblk0p1.";
      };
    }
    {
      name = "secondary_gpt";
      type = "secondary_gpt";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0xFFFFFFFFFFFFFFFF";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
  ];

  # Build the final flash.xml by replacing the storage-device partitions
  # in NVIDIA's template with our layout using XML-aware splicing.
  #
  # The Orin NX SOM has no eMMC; the p3768 devkit boots its rootfs from
  # NVMe. Splice into the nvme template + device element instead of
  # sdmmc_user, otherwise MB2 probes SDMMC instance 3 at flash time,
  # fails ("Secondary storage init failed"), and hangs in Busy Spin.
  partitionTemplate =
    let
      inherit (pkgs.nvidia-jetpack) bspSrc;
      inherit (config.hardware.nvidia-jetpack) som;
      isIndustrial = som == "orin-agx-industrial";
      isNvme = som == "orin-nx";
      xmlFile =
        if isIndustrial then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml"
        else if isNvme then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_nvme.xml"
        else
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";
    in
    pkgs.runCommand "flash.xml"
      {
        nativeBuildInputs = [ pkgs.buildPackages.python3 ];
      }
      ''
        python3 ${./splice-flash-xml.py} \
          --device-type "${if isNvme then "nvme" else "sdmmc_user"}" \
          ${lib.optionalString cfg.flashScriptOverrides.onlyQSPI "--remove-device"} \
          --set "esp.size=$(($(cat ${images}/esp.size) * 512))" \
          --set "APP.size=$(($(cat ${images}/root.size) * 512))" \
          ${xmlFile} \
          ${pkgs.writeText "sdmmc.json" (builtins.toJSON partitionsEmmc)} \
          "$out"
      '';

  # preFlashCommands: Extract images from sdImage and patch flash.xml
  preFlashScript = pkgs.writeShellApplication {
    name = "pre-flash-commands";
    runtimeInputs = [
      pkgs.pkgsBuildBuild.zstd
      pkgs.pkgsBuildBuild.gnused
      pkgs.pkgsBuildBuild.cryptsetup
      pkgs.pkgsBuildBuild.e2fsprogs
      pkgs.pkgsBuildBuild.coreutils
      pkgs.pkgsBuildBuild.util-linux
    ];
    text = ''
      echo "============================================================"
      echo "Ghaf flash script for NVIDIA Jetson"
      echo "============================================================"
      echo "Version: ${config.ghaf.version}"
      echo "SoM: ${config.hardware.nvidia-jetpack.som}"
      echo "Carrier board: ${config.hardware.nvidia-jetpack.carrierBoard}"
      echo "Disk encryption: ${lib.boolToString cfg.diskEncryption.enable}"
      echo "============================================================"
      echo ""
      WORKDIR=$PWD
      mkdir -pv "$WORKDIR/bootloader"
      rm -fv "$WORKDIR/bootloader/esp.img"

      ${lib.optionalString (cfg.flashScriptOverrides.signedArtifactsPath != null) ''
        if [ -z "''${SIGNED_ARTIFACTS_DIR:-}" ]; then
          SIGNED_ARTIFACTS_DIR=${lib.escapeShellArg cfg.flashScriptOverrides.signedArtifactsPath}
        fi
      ''}

      if [ -n "''${SIGNED_ARTIFACTS_DIR:-}" ]; then
        echo "Using signed artifacts from $SIGNED_ARTIFACTS_DIR"

        for artifact in BOOTAA64.EFI Image; do
          if [ ! -f "$SIGNED_ARTIFACTS_DIR/$artifact" ]; then
            echo "ERROR: Missing $artifact in $SIGNED_ARTIFACTS_DIR" >&2
            exit 1
          fi
        done

        export BOOTAA64_EFI="$SIGNED_ARTIFACTS_DIR/BOOTAA64.EFI"
        export KERNEL_IMAGE="$SIGNED_ARTIFACTS_DIR/Image"

        # NOTE: initrd and DTB swaps are currently a no-op for Secure Boot.
        # UEFI on Orin only verifies the loaded EFI binary (BOOTAA64.EFI);
        # the kernel Image, initrd, and devicetree are loaded by systemd-boot
        # after handoff and are not part of the SB measurement chain. These
        # swaps exist so a signed-image build can ship matching artifacts,
        # but they do not extend the trust boundary on their own. Closing
        # this gap (UKI bundling the kernel/initrd/cmdline into the signed
        # PE, plus DTB measurement / signing) is tracked separately and is
        # a prerequisite for disk encryption rooted in firmware trust.
        if [ -f "$SIGNED_ARTIFACTS_DIR/initrd" ]; then
          export INITRD_IMAGE="$SIGNED_ARTIFACTS_DIR/initrd"
        fi

        if [ -f "$SIGNED_ARTIFACTS_DIR/dtb" ]; then
          export DTB_IMAGE="$SIGNED_ARTIFACTS_DIR/dtb"
        fi
      fi

      if [ -n "''${BOOTAA64_EFI:-}" ]; then
        if [ ! -f "$BOOTAA64_EFI" ]; then
          echo "ERROR: BOOTAA64_EFI not found: $BOOTAA64_EFI" >&2
          exit 1
        fi
        echo "Using external BOOTAA64.EFI: $BOOTAA64_EFI"
        cp -f "$BOOTAA64_EFI" "$WORKDIR/bootloader/BOOTAA64.efi"
      fi

      if [ -n "''${KERNEL_IMAGE:-}" ]; then
        if [ ! -f "$KERNEL_IMAGE" ]; then
          echo "ERROR: KERNEL_IMAGE not found: $KERNEL_IMAGE" >&2
          exit 1
        fi
        echo "Using external kernel Image: $KERNEL_IMAGE"
        mkdir -pv "$WORKDIR/kernel"
        cp -f "$KERNEL_IMAGE" "$WORKDIR/kernel/Image"
      fi

      ${lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
        image_source_root=${lib.escapeShellArg (toString images)}

        if [ -n "''${SIGNED_SD_IMAGE_DIR:-}" ]; then
          if [ ! -d "$SIGNED_SD_IMAGE_DIR" ]; then
            echo "ERROR: SIGNED_SD_IMAGE_DIR not found: $SIGNED_SD_IMAGE_DIR" >&2
            exit 1
          fi
          image_source_root="$SIGNED_SD_IMAGE_DIR"
        fi

        # Read partition offsets and sizes from sdImage metadata
        ESP_OFFSET=$(cat "$image_source_root/esp.offset")
        ESP_SIZE=$(cat "$image_source_root/esp.size")
        ROOT_OFFSET=$(cat "$image_source_root/root.offset")
        ROOT_SIZE=$(cat "$image_source_root/root.size")

        img=$(find "$image_source_root" -maxdepth 1 -name '*.img.zst' -print -quit)
        if [ -z "$img" ]; then
          img=$(find "$image_source_root/sd-image" -maxdepth 1 -name '*.img.zst' -print -quit 2>/dev/null || true)
        fi
        if [ -z "$img" ]; then
          echo "ERROR: No .img.zst found in $image_source_root/sd-image or $image_source_root" >&2
          exit 1
        fi

        echo "Source image: $img"
        echo "ESP: offset=$ESP_OFFSET sectors, size=$ESP_SIZE sectors"
        echo "Root: offset=$ROOT_OFFSET sectors, size=$ROOT_SIZE sectors"
        echo ""

        echo "Extracting ESP partition..."
        dd if=<(pzstd -d "$img" -c) \
           of="$WORKDIR/bootloader/esp.img" \
           bs=512 iseek="$ESP_OFFSET" count="$ESP_SIZE" status=progress

        echo "Extracting root partition..."
        ROOT_IMAGE_PATH="$WORKDIR/bootloader/root.img"
        dd if=<(pzstd -d "$img" -c) \
           of="$ROOT_IMAGE_PATH" \
           bs=512 iseek="$ROOT_OFFSET" count="$ROOT_SIZE" status=progress

        ${lib.optionalString cfg.diskEncryption.enable ''
          echo ""
          echo "Generic LUKS rootfs encryption is enabled."
          GHAF_SKIP_LUKS_ENCRYPTION=0
          ROOT_PLAINTEXT_IMAGE="$WORKDIR/bootloader/root.img"
          ROOT_IMAGE_PATH="$WORKDIR/bootloader/root.enc.img"
          LUKS_REDUCTION_BYTES=$((16 * 1024 * 1024))
          LUKS_DATA_OFFSET_BYTES=$((8 * 1024 * 1024))
          # Host-side verification of root.enc.img shows the mapped device ends up
          # four additional LUKS data offsets smaller than the final image file.
          # Account for that before reencrypting so the ext4 filesystem fits the
          # post-conversion payload exactly.
          LUKS_PAYLOAD_SLACK_BYTES=$((4 * LUKS_DATA_OFFSET_BYTES))

          if [ -n "''${GHAF_LUKS_PASSPHRASE-}" ]; then
            GHAF_LUKS_PASSPHRASE_CONFIRM="$GHAF_LUKS_PASSPHRASE"
          elif [ -t 0 ] && [ -t 1 ]; then
            while true; do
              read -r -s -p "Enter shared LUKS passphrase: " GHAF_LUKS_PASSPHRASE
              echo ""
              read -r -s -p "Confirm shared LUKS passphrase: " GHAF_LUKS_PASSPHRASE_CONFIRM
              echo ""

              if [ -z "$GHAF_LUKS_PASSPHRASE" ]; then
                echo "Passphrase cannot be empty."
                continue
              fi

              if [ "$GHAF_LUKS_PASSPHRASE" != "$GHAF_LUKS_PASSPHRASE_CONFIRM" ]; then
                echo "Passphrases do not match. Try again."
                continue
              fi

              break
            done
          else
            GHAF_SKIP_LUKS_ENCRYPTION=1
            echo "Non-interactive environment without GHAF_LUKS_PASSPHRASE; skipping root image encryption."
          fi

          if [ "$GHAF_SKIP_LUKS_ENCRYPTION" -eq 0 ]; then
            GHAF_LUKS_PASSPHRASE_FILE=$(mktemp "$WORKDIR/.luks-passphrase.XXXXXX")
            chmod 600 "$GHAF_LUKS_PASSPHRASE_FILE"
            printf '%s' "$GHAF_LUKS_PASSPHRASE" > "$GHAF_LUKS_PASSPHRASE_FILE"
            unset GHAF_LUKS_PASSPHRASE GHAF_LUKS_PASSPHRASE_CONFIRM

            echo "Shrinking plaintext root filesystem before LUKS conversion ..."
            e2fsck -fy "$ROOT_PLAINTEXT_IMAGE"
            BLOCK_SIZE=$(dumpe2fs -h "$ROOT_PLAINTEXT_IMAGE" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
            TARGET_PAYLOAD_BYTES=$(( $(stat -c %s "$ROOT_PLAINTEXT_IMAGE") - LUKS_REDUCTION_BYTES - LUKS_DATA_OFFSET_BYTES - LUKS_PAYLOAD_SLACK_BYTES ))
            TARGET_BLOCKS=$(( TARGET_PAYLOAD_BYTES / BLOCK_SIZE ))
            resize2fs "$ROOT_PLAINTEXT_IMAGE" "$TARGET_BLOCKS"
            # Keep the plaintext file one LUKS data offset larger than the
            # ext4 payload so reencrypt does not collapse the final image size
            # together with the resized filesystem.
            truncate -s "$(( TARGET_PAYLOAD_BYTES + LUKS_DATA_OFFSET_BYTES ))" "$ROOT_PLAINTEXT_IMAGE"

            echo "Encrypting extracted root image with LUKS2 ..."
            cryptsetup reencrypt \
              --encrypt \
              --type luks2 \
              --batch-mode \
              --reduce-device-size "$LUKS_REDUCTION_BYTES" \
              --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
              "$ROOT_PLAINTEXT_IMAGE"

            mv "$ROOT_PLAINTEXT_IMAGE" "$ROOT_IMAGE_PATH"

            # Re-materialize the final APP image as a fully allocated raw file.
            # The flash pipeline should see a dense payload, not a sparse file
            # with holes introduced by truncate during the sizing step above.
            ROOT_IMAGE_DENSE_PATH="$WORKDIR/bootloader/root.enc.dense.img"
            cp --sparse=never "$ROOT_IMAGE_PATH" "$ROOT_IMAGE_DENSE_PATH"
            mv "$ROOT_IMAGE_DENSE_PATH" "$ROOT_IMAGE_PATH"

            if [ "''${GHAF_LUKS_CHECK_GEOMETRY:-0}" = "1" ]; then
              echo "Checking encrypted root image geometry ..."
              cryptsetup close ghaf-luks-verify 2>/dev/null || true
              GEOMETRY_LOOPDEV=$(losetup --find --show "$ROOT_IMAGE_PATH")
              cryptsetup open \
                --readonly \
                --type luks \
                --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
                "$GEOMETRY_LOOPDEV" ghaf-luks-verify
              MAPPER_BYTES=$(blockdev --getsize64 /dev/mapper/ghaf-luks-verify)
              FS_BLOCK_COUNT=$(dumpe2fs -h /dev/mapper/ghaf-luks-verify 2>/dev/null | sed -n 's/^Block count:[[:space:]]*//p')
              FS_BLOCK_SIZE=$(dumpe2fs -h /dev/mapper/ghaf-luks-verify 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
              FS_BYTES=$(( FS_BLOCK_COUNT * FS_BLOCK_SIZE ))
              echo "Encrypted image bytes: $(stat -c %s "$ROOT_IMAGE_PATH")"
              echo "Mapped payload bytes: $MAPPER_BYTES"
              echo "Ext4 filesystem bytes: $FS_BYTES"
              if [ "$FS_BYTES" -ne "$MAPPER_BYTES" ]; then
                echo "ERROR: ext4 filesystem does not fit encrypted payload." >&2
                cryptsetup close ghaf-luks-verify
                losetup -d "$GEOMETRY_LOOPDEV"
                exit 1
              fi
              cryptsetup close ghaf-luks-verify
              losetup -d "$GEOMETRY_LOOPDEV"
            fi

            if [ "''${GHAF_LUKS_VALIDATE_IMAGE:-0}" = "1" ]; then
              echo "Validating encrypted root image ..."
              cryptsetup close ghaf-luks-verify 2>/dev/null || true
              VALIDATE_LOOPDEV=$(losetup --find --show "$ROOT_IMAGE_PATH")
              cryptsetup open \
                --type luks \
                --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
                "$VALIDATE_LOOPDEV" ghaf-luks-verify
              tune2fs -l /dev/mapper/ghaf-luks-verify >/dev/null
              if [ "''${GHAF_LUKS_VALIDATE_FULL_FSCK:-0}" = "1" ]; then
                echo "Running full fsck validation on encrypted root image ..."
                e2fsck -fn /dev/mapper/ghaf-luks-verify
              fi
              cryptsetup close ghaf-luks-verify
              losetup -d "$VALIDATE_LOOPDEV"
            fi

            rm -f "$GHAF_LUKS_PASSPHRASE_FILE"
          fi
        ''}

        echo ""
        echo "Patching flash.xml with image paths and sizes..."
        ROOT_IMAGE_SIZE_BYTES=$(stat -c %s "$ROOT_IMAGE_PATH")
        sed -i \
          -e "s#bootloader/esp.img#$WORKDIR/bootloader/esp.img#" \
          -e "s#root.img#$ROOT_IMAGE_PATH#" \
          -e "s#ESP_SIZE#$((ESP_SIZE * 512))#" \
          -e "s#ROOT_SIZE#$ROOT_IMAGE_SIZE_BYTES#" \
          flash.xml
      ''}

      ${lib.optionalString cfg.flashScriptOverrides.onlyQSPI ''
        echo "QSPI-only mode: skipping ESP and root partition extraction."
      ''}

      echo ""
      echo "Ready to flash!"
      echo "============================================================"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    hardware.nvidia-jetpack.flashScriptOverrides.preFlashCommands = "${preFlashScript}/bin/pre-flash-commands";
    hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;
  };
}
