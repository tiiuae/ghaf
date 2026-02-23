# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Partition template for A/B verity boot on NVIDIA Jetson Orin AGX.
#
# Produces a flash.xml with two partitions on eMMC:
#   - ESP (512M, vfat) with systemd-boot + UKI
#   - APP (LVM PV) with A/B root+verity slots, swap, persist
#
# preFlashCommands copies pre-built images from verity-image.nix into the
# flash workdir and patches flash.xml with actual paths and sizes.
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;

  inherit (config.system.build) verityImages;

  # eMMC partition layout as structured Nix data.
  # Serialized to JSON and spliced into NVIDIA's flash XML by
  # splice-flash-xml.py, which replaces the <device type="sdmmc_user">
  # children. This avoids fragile line-count splicing.
  #
  # All values are fully resolved at Nix build time (the APP partition
  # size is read from the LVM image derivation via --set).
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
        size = "536870912";
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        percent_reserved = "0";
        filename = "esp.img";
        partition_type_guid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
        description = "EFI system partition with systemd-boot + UKI.";
      };
    }
    {
      name = "APP";
      type = "data";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0"; # overridden by --set from verityImages at build time
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        align_boundary = "16384";
        percent_reserved = "0x808";
        unique_guid = "APPUUID";
        filename = "system.img";
        description = "LVM PV containing A/B root+verity slots, swap, persist.";
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
    pkgs.runCommand "flash-verity.xml"
      {
        nativeBuildInputs = [ pkgs.buildPackages.python3 ];
      }
      ''
        python3 ${./splice-flash-xml.py} \
          --set "APP.size=$(cat ${verityImages}/system.raw_size)" \
          ${xmlFile} \
          ${pkgs.writeText "sdmmc-verity.json" (builtins.toJSON partitionsEmmc)} \
          "$out"
      '';

  # preFlashCommands: Copy pre-built images and patch flash.xml
  preFlashCommands = ''
    echo "============================================================"
    echo "Ghaf A/B verity flash script for NVIDIA Jetson"
    echo "============================================================"
    echo "Version: ${config.ghaf.version}"
    echo "SoM: ${config.hardware.nvidia-jetpack.som}"
    echo "Carrier board: ${config.hardware.nvidia-jetpack.carrierBoard}"
    echo "============================================================"
    echo ""

    mkdir -pv "$WORKDIR/bootloader"

    # jetpack-nixos sets NO_ESP_IMG=1; override so flash.sh assigns
    # localespfile=esp.img (needed for -k esp). The -r flag already
    # prevents flash.sh from rebuilding esp.img via create_espimage.
    export NO_ESP_IMG=0

    echo "Decompressing pre-built ESP image..."
    "${pkgs.pkgsBuildBuild.zstd}/bin/zstd" -f -d "${verityImages}/esp.img.zst" -o "$WORKDIR/bootloader/esp.img"

    echo "Decompressing pre-built system (LVM) sparse image..."
    "${pkgs.pkgsBuildBuild.zstd}/bin/zstd" -f -d "${verityImages}/system.img.zst" -o "$WORKDIR/bootloader/system.img"
    # flash.sh -k APP looks for system.img relative to $WORKDIR
    ln -sf "$WORKDIR/bootloader/system.img" "$WORKDIR/system.img"
    echo "LVM image: $("${pkgs.pkgsBuildBuild.coreutils}/bin/stat" -c%s "$WORKDIR/bootloader/system.img") bytes (compressed)"

    # Ensure all DTB variants in kernel/dtb/ have NixOS overlays applied.
    # NixOS only applies deviceTree.overlays to the DTB named in
    # hardware.deviceTree.name, but flash.sh picks a variant based on
    # the board's EEPROM SKU (e.g. p3701-0005 instead of p3701-0000).
    # Derive a glob from the configured DTB name by replacing the SOM
    # revision with a wildcard, then copy the composed DTB over all
    # matching variants so the overlay (notably PCI passthrough
    # iommus=<> fix) is always present in the firmware DTB.
    #
    # Example: tegra234-p3737-0000+p3701-0000-nv.dtb
    #        → tegra234-p3737-0000+p3701-*-nv.dtb
    echo "Copying composed DTB over all SOM variant DTBs..."
    chmod -R u+w kernel/dtb/
    composed="kernel/dtb/${config.hardware.deviceTree.name}"
    # Replace the last 4-digit revision before -nv.dtb with a wildcard
    dtb_glob="kernel/dtb/$(echo "${config.hardware.deviceTree.name}" | "${pkgs.pkgsBuildBuild.gnused}/bin/sed" 's/-[0-9]\{4\}-nv\.dtb$/-*-nv.dtb/')"
    for variant in $dtb_glob; do
      if [ "$variant" != "$composed" ]; then
        echo "  $composed -> $(basename "$variant")"
        cp "$composed" "$variant"
      fi
    done

    echo ""
    echo "Ready to flash!"
    echo "============================================================"
  '';
in
{
  config = lib.mkIf (cfg.enable && config.ghaf.partitioning.verity-volume.enable) {
    hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;
    hardware.nvidia-jetpack.flashScriptOverrides.preFlashCommands = preFlashCommands;
  };
}
