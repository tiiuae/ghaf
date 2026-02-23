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

  # Partition XML with placeholders (substituted at flash time by preFlashCommands)
  partitionsEmmc = pkgs.writeText "sdmmc-verity.xml" ''
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
      <size> 536870912 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
      <filename> ESP_IMG_PATH </filename>
      <partition_type_guid> C12A7328-F81F-11D2-BA4B-00A0C93EC93B </partition_type_guid>
      <description> EFI system partition with systemd-boot + UKI. </description>
    </partition>
    <partition name="APP" id="1" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> LVM_SIZE </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <align_boundary> 16384 </align_boundary>
      <percent_reserved> 0x808 </percent_reserved>
      <unique_guid> APPUUID </unique_guid>
      <filename> LVM_IMG_PATH </filename>
      <description> LVM PV containing A/B root+verity slots, swap, persist. </description>
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
      {
        firstLineCount = 631;
        lastLineCount = 2;
      }
    else
      {
        firstLineCount = 618;
        lastLineCount = 2;
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
    pkgs.runCommand "flash-verity.xml" { } ''
      head -n ${toString partitionTemplateReplaceRange.firstLineCount} ${xmlFile} >"$out"
      cat ${partitionsEmmc} >>"$out"
      tail -n ${toString partitionTemplateReplaceRange.lastLineCount} ${xmlFile} >>"$out"
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

    LVM_SIZE=$(cat "${verityImages}/system.raw_size")
    echo "LVM raw size: $LVM_SIZE bytes (sparse image: $("${pkgs.pkgsBuildBuild.coreutils}/bin/stat" -c%s "$WORKDIR/bootloader/system.img") bytes)"

    echo "Patching flash.xml with image paths and sizes..."
    "${pkgs.pkgsBuildBuild.gnused}/bin/sed" -i \
      -e "s#ESP_IMG_PATH#esp.img#" \
      -e "s#LVM_IMG_PATH#system.img#" \
      -e "s#LVM_SIZE#$LVM_SIZE#" \
      flash.xml

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
