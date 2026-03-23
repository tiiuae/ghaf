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

  # Build the final flash.xml by replacing the sdmmc_user partitions
  # in NVIDIA's template with our layout using XML-aware splicing.
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
    pkgs.runCommand "flash.xml"
      {
        nativeBuildInputs = [ pkgs.buildPackages.python3 ];
      }
      ''
        python3 ${./splice-flash-xml.py} \
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
        dd if=<(pzstd -d "$img" -c) \
           of="$WORKDIR/bootloader/root.img" \
           bs=512 iseek="$ROOT_OFFSET" count="$ROOT_SIZE" status=progress

        echo ""
        echo "Patching flash.xml with image paths..."
        sed -i \
          -e "s#bootloader/esp.img#$WORKDIR/bootloader/esp.img#" \
          -e "s#root.img#$WORKDIR/bootloader/root.img#" \
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
