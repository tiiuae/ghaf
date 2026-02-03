# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which provides partition template for NVIDIA Jetson AGX Orin
# flash-script
{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Using the same config for all orin boards (for now)
  # TODO should this be changed when NX added
  cfg = config.ghaf.hardware.nvidia.orin;

  images = config.system.build.${config.formatAttr};
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
  # When updating jetpack-nixos version, if the flash_t234_qspi_sdmmc.xml
  # changes (usually if the underlying BSP-version changes), you might need to
  # update the magical numbers to match the latest flash_t234_qspi_sdmmc.xml if
  # it has changed. The point is to replace content between
  # `partitionTemplateReplaceRange.firstLineCount` first lines and
  # `partitionTemplateReplaceRange.lastLineCount` last lines (i.e. the content
  # of the <device type="sdmmc_user" ...> </device> XML-tag), from the
  # NVIDIA-supplied flash_t234_qspi_sdmmc.xml, with the partitions specified in
  # the above partitionsEmmc variable.
  # Orin AGX Industrial has a slightly different flash XML template, so we
  # need to handle that separately.
  # it uses flash_t234_qspi_sdmmc_industrial.xml as a base and the sdmmc section
  # starts and ends at different lines.
  partitionTemplateReplaceRange =
    if (config.hardware.nvidia-jetpack.som == "orin-agx-industrial") then
      if (!cfg.flashScriptOverrides.onlyQSPI) then
        {
          firstLineCount = 631;
          lastLineCount = 2;
        }
      else
        {
          # If we don't flash anything to eMMC, then we don't need to have the
          # <device type="sdmmc_user" ...> </device> XML-tag at all.
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
        # If we don't flash anything to eMMC, then we don't need to have the
        # <device type="sdmmc_user" ...> </device> XML-tag at all.
        firstLineCount = 617;
        lastLineCount = 1;
      };
  partitionTemplate = pkgs.runCommand "flash.xml" { } (
    lib.optionalString (config.hardware.nvidia-jetpack.som != "orin-agx-industrial") ''
      head -n ${toString partitionTemplateReplaceRange.firstLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml >"$out"

    ''
    + lib.optionalString (config.hardware.nvidia-jetpack.som == "orin-agx-industrial") ''
      head -n ${toString partitionTemplateReplaceRange.firstLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml >"$out"

    ''
    + lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''

      # Replace the section for sdmmc-device with our own section
      cat ${partitionsEmmc} >>"$out"

    ''
    + lib.optionalString (config.hardware.nvidia-jetpack.som != "orin-agx-industrial") ''

      tail -n ${toString partitionTemplateReplaceRange.lastLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml >>"$out"
    ''
    + lib.optionalString (config.hardware.nvidia-jetpack.som == "orin-agx-industrial") ''

      tail -n ${toString partitionTemplateReplaceRange.lastLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml >>"$out"
    ''
  );
  # Expose the partition template and preFlashCommands as ghaf options
  # These will be set on hardware.nvidia-jetpack.flashScriptOverrides
  # in the individual device configuration files
  ghafPartitionTemplate = partitionTemplate;

  ghafPreFlashCommands = ''
    echo "============================================================"
    echo "ghaf flashing script"
    echo "============================================================"
    echo "ghaf version: ${config.ghaf.version}"
    echo "som: ${config.hardware.nvidia-jetpack.som}"
    echo "carrierBoard: ${config.hardware.nvidia-jetpack.carrierBoard}"
    echo "============================================================"
    echo ""
    echo "Working dir: $WORKDIR"
    echo "Removing bootlodaer/esp.img if it exists ..."
    rm -fv "$WORKDIR/bootloader/esp.img"
    mkdir -pv "$WORKDIR/bootloader"

    # See https://developer.download.nvidia.com/embedded/L4T/r35_Release_v4.1/docs/Jetson_Linux_Release_Notes_r35.4.1.pdf
    # and https://developer.download.nvidia.com/embedded/L4T/r35_Release_v5.0/docs/Jetson_Linux_Release_Notes_r35.5.0.pdf
    #
    # In Section: Adaptation to the Carrier Board with HDMI for the Orin
    #             NX/Nano Modules
    #"${pkgs.pkgsBuildBuild.patch}/bin/patch" -p0 < ${./tegra2-mb2-bct-scr.patch}
  ''
  + lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
    ESP_OFFSET=$(cat "${images}/esp.offset")
    ESP_SIZE=$(cat "${images}/esp.size")
    ROOT_OFFSET=$(cat "${images}/root.offset")
    ROOT_SIZE=$(cat "${images}/root.size")

    img="${images}/sd-image/${config.image.fileName}"
    echo "Extracting ESP partition to $WORKDIR/bootloader/esp.img ..."
    dd if=<("${pkgs.pkgsBuildBuild.zstd}/bin/pzstd" -d "$img" -c) of="$WORKDIR/bootloader/esp.img" bs=512 iseek="$ESP_OFFSET" count="$ESP_SIZE"
    echo "Extracting root partition to $WORKDIR/root.img ..."
    dd if=<("${pkgs.pkgsBuildBuild.zstd}/bin/pzstd" -d "$img" -c) of="$WORKDIR/bootloader/root.img" bs=512 iseek="$ROOT_OFFSET" count="$ROOT_SIZE"

    echo "Patching flash.xml with absolute paths to esp.img and root.img ..."
    "${pkgs.pkgsBuildBuild.gnused}/bin/sed" -i \
      -e "s#bootloader/esp.img#$WORKDIR/bootloader/esp.img#" \
      -e "s#root.img#$WORKDIR/root.img#" \
      -e "s#ESP_SIZE#$((ESP_SIZE * 512))#" \
      -e "s#ROOT_SIZE#$((ROOT_SIZE * 512))#" \
      flash.xml

  ''
  + lib.optionalString cfg.flashScriptOverrides.onlyQSPI ''
    echo "Flashing QSPI only, boot and root images not included."
  ''
  + ''
    echo "Ready to flash!"
    echo "============================================================"
    echo ""
  '';
in
{
  options.ghaf.hardware.nvidia.orin = {
    flashScriptOverrides.partitionTemplate = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "Generated partition template for flashing";
    };

    flashScriptOverrides.preFlashCommands = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Generated pre-flash commands for flashing";
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose the generated partition template and preFlashCommands
    # These are set directly on hardware.nvidia-jetpack.flashScriptOverrides
    # in the device-specific configuration files (orin-agx.nix, etc.)
    ghaf.hardware.nvidia.orin.flashScriptOverrides.partitionTemplate = ghafPartitionTemplate;
    ghaf.hardware.nvidia.orin.flashScriptOverrides.preFlashCommands = ghafPreFlashCommands;
  };
}
