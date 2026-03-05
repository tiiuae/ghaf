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

  # sdImage containing ESP and root partitions (compressed)
  images = config.system.build.sdImage;

  # Partition XML with placeholders (substituted at flash time by preFlashCommands)
  partitionsEmmc = pkgs.writeText "sdmmc.xml" ''
    <partition name="master_boot_record" type="protective_master_boot_record">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 512 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
    <partition name="primary_gpt" type="primary_gpt">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 19968 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
    <partition name="esp" id="2" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> ESP_SIZE </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
      <filename> bootloader/esp.img </filename>
      <partition_type_guid> C12A7328-F81F-11D2-BA4B-00A0C93EC93B </partition_type_guid>
      <description> EFI system partition with systemd-boot. </description>
    </partition>
    <partition name="APP" id="1" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> ROOT_SIZE </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <align_boundary> 16384 </align_boundary>
      <percent_reserved> 0x808 </percent_reserved>
      <unique_guid> APPUUID </unique_guid>
      <filename> root.img </filename>
      <description> **Required.** Contains the rootfs. This partition must be assigned
        the "1" for id as it is physically put to the end of the device, so that it
        can be accessed as the fixed known special device `/dev/mmcblk0p1`. </description>
    </partition>
    <partition name="secondary_gpt" type="secondary_gpt">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 0xFFFFFFFFFFFFFFFF </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
  '';

  # Line counts for replacing the sdmmc_user device section in NVIDIA's flash XML.
  # These numbers specify where to splice our custom partition layout.
  #
  # WARNING: When updating jetpack-nixos/BSP version, verify these line counts
  # still match the <device type="sdmmc_user"> section boundaries in:
  # - flash_t234_qspi_sdmmc.xml (standard)
  # - flash_t234_qspi_sdmmc_industrial.xml (industrial variant)
  partitionTemplateReplaceRange =
    if (config.hardware.nvidia-jetpack.som == "orin-agx-industrial") then
      if (!cfg.flashScriptOverrides.onlyQSPI) then
        {
          firstLineCount = 631;
          lastLineCount = 2;
        }
      else
        {
          # QSPI-only: remove entire sdmmc_user device section
          firstLineCount = 630;
          lastLineCount = 1;
        }
    else if !cfg.flashScriptOverrides.onlyQSPI then
      {
        firstLineCount = 618;
        lastLineCount = 2;
      }
    else
      {
        # QSPI-only: remove entire sdmmc_user device section
        firstLineCount = 617;
        lastLineCount = 1;
      };

  # Build the final flash.xml by splicing our partition layout into NVIDIA's template
  partitionTemplate =
    let
      inherit (pkgs.nvidia-jetpack) bspSrc;
      isIndustrial = config.hardware.nvidia-jetpack.som == "orin-agx-industrial";
      xmlFile =
        if isIndustrial then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml"
        else
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";
    in
    pkgs.runCommand "flash.xml" { } (
      ''
        head -n ${toString partitionTemplateReplaceRange.firstLineCount} ${xmlFile} >"$out"
      ''
      + lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
        cat ${partitionsEmmc} >>"$out"
      ''
      + ''
        tail -n ${toString partitionTemplateReplaceRange.lastLineCount} ${xmlFile} >>"$out"
      ''
    );

  # preFlashCommands: Extract images from sdImage and patch flash.xml
  preFlashScript = pkgs.writeShellApplication {
    name = "pre-flash-commands";
    runtimeInputs = [
      pkgs.pkgsBuildBuild.zstd
      pkgs.pkgsBuildBuild.gnused
      pkgs.pkgsBuildBuild.cryptsetup
    ];
    text = ''
      echo "============================================================"
      echo "Ghaf flash script for NVIDIA Jetson"
      echo "============================================================"
      echo "Version: ${config.ghaf.version}"
      echo "SoM: ${config.hardware.nvidia-jetpack.som}"
      echo "Carrier board: ${config.hardware.nvidia-jetpack.carrierBoard}"
      echo "============================================================"
      echo ""
      WORKDIR=$PWD
      mkdir -pv "$WORKDIR/bootloader"
      rm -fv "$WORKDIR/bootloader/esp.img"

      ${lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
        # Read partition offsets and sizes from sdImage metadata
        ESP_OFFSET=$(cat "${images}/esp.offset")
        ESP_SIZE=$(cat "${images}/esp.size")
        ROOT_OFFSET=$(cat "${images}/root.offset")
        ROOT_SIZE=$(cat "${images}/root.size")

        img="${images}/sd-image/${config.image.fileName}"
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
        ${lib.optionalString cfg.diskEncryption.enable ''
          ROOT_IMAGE_PATH="$WORKDIR/bootloader/root.enc.img"
        ''}
        dd if=<(pzstd -d "$img" -c) \
           of="$ROOT_IMAGE_PATH" \
           bs=512 iseek="$ROOT_OFFSET" count="$ROOT_SIZE" status=progress

        ${lib.optionalString cfg.diskEncryption.enable ''
          echo ""
          echo "Generic LUKS rootfs encryption is enabled."
          GHAF_SKIP_LUKS_ENCRYPTION=0

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

            echo "Encrypting extracted root image with LUKS2 ..."
            cryptsetup reencrypt \
              --encrypt \
              --type luks2 \
              --batch-mode \
              --reduce-device-size $((16 * 1024 * 1024)) \
              --key-file "$GHAF_LUKS_PASSPHRASE_FILE" \
              "$ROOT_IMAGE_PATH"

            rm -f "$GHAF_LUKS_PASSPHRASE_FILE"
          fi
        ''}

        echo ""
        echo "Patching flash.xml with image paths and sizes..."
        sed -i \
          -e "s#bootloader/esp.img#$WORKDIR/bootloader/esp.img#" \
          -e "s#root.img#$ROOT_IMAGE_PATH#" \
          -e "s#ESP_SIZE#$((ESP_SIZE * 512))#" \
          -e "s#ROOT_SIZE#$((ROOT_SIZE * 512))#" \
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
    hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;
    hardware.nvidia-jetpack.flashScriptOverrides.preFlashCommands = "${preFlashScript}/bin/pre-flash-commands";
  };
}
