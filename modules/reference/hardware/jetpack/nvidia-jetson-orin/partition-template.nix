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
