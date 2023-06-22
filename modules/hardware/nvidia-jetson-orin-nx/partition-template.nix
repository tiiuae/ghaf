# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which provides partition template for NVIDIA Jetson AGX Orin
# flash-script
{
  pkgs,
  config,
  ...
}: let
  mkSplitImages = import ./mk-split-images.nix;
  images = mkSplitImages {
    inherit pkgs;
    src = config.system.build.${config.formatAttr};
  };
  espSize = builtins.readFile "${images}/esp.size";
  rootSize = builtins.readFile "${images}/root.size";
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
      <size> ${espSize} </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
      <filename> ${images}/esp.img </filename>
      <partition_type_guid> C12A7328-F81F-11D2-BA4B-00A0C93EC93B </partition_type_guid>
      <description> EFI system partition with systemd-boot. </description>
    </partition>
    <partition name="APP" id="1" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> ${rootSize} </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <align_boundary> 16384 </align_boundary>
      <percent_reserved> 0 </percent_reserved>
      <unique_guid> APPUUID </unique_guid>
      <filename> ${images}/root.img </filename>
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
  partitionTemplateReplaceRange = {
    firstLineCount = 588;
    lastLineCount = 2;
  };
  partitionTemplate = pkgs.runCommand "flash.xml" {} ''
    head -n ${builtins.toString partitionTemplateReplaceRange.firstLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml >$out

    # Replace the section for sdmmc-device with our own section
    cat ${partitionsEmmc} >>$out

    tail -n ${builtins.toString partitionTemplateReplaceRange.lastLineCount} ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml >>$out
  '';
in {
  hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;

  imports = [
    ./flash-script-overrides.nix
  ];

  ghaf.nvidia-jetpack.flashScriptOverrides.preFlashCommands = ''
    ln -sf ${images}/esp.img bootloader/esp.img
  '';
}
