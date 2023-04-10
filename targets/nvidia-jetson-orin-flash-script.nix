# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  nixpkgs,
  package,
  hostConfiguration,
}: let
  images = nixpkgs.legacyPackages.x86_64-linux.stdenvNoCC.mkDerivation {
    src = package;
    name = "split-images";
    nativeBuildInputs = [nixpkgs.legacyPackages.x86_64-linux.util-linux];
    installPhase = ''
      img="./nixos.img"
      fdisk_output=$(fdisk -l "$img")

      # Offsets and sizes are in 512 byte sectors
      blocksize=512

      # ESP partition offset and sector count
      part_esp=$(echo -n "$fdisk_output" | tail -n 2 | head -n 1 | tr -s ' ')
      part_esp_begin=$(echo -n "$part_esp" | cut -d ' ' -f2)
      part_esp_count=$(echo -n "$part_esp" | cut -d ' ' -f4)

      # root-partition offset and sector count
      part_root=$(echo -n "$fdisk_output" | tail -n 1 | head -n 1 | tr -s ' ')
      part_root_begin=$(echo -n "$part_root" | cut -d ' ' -f2)
      part_root_count=$(echo -n "$part_root" | cut -d ' ' -f4)

      # Extract partitions to separate files
      mkdir -p $out
      dd if=$img of=$out/esp.img bs=$blocksize skip=$part_esp_begin count=$part_esp_count
      dd if=$img of=$out/root.img bs=$blocksize skip=$part_root_begin count=$part_root_count

      # Save partition sizes in bytes to be included in partition layout
      echo -n $(($part_esp_count * 512)) > $out/esp.size
      echo -n $(($part_root_count * 512)) > $out/root.size
    '';
  };
  espSize = builtins.readFile "${images}/esp.size";
  rootSize = builtins.readFile "${images}/root.size";
  partitionsEmmc = nixpkgs.legacyPackages.x86_64-linux.writeText "sdmmc.xml" ''
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

  # Flash Options module
  flashOptions = {
    pkgs,
    lib,
    config,
    ...
  }: let
    partitionTemplate = nixpkgs.legacyPackages.x86_64-linux.runCommand "flash.xml" {} ''
      head -n 588 ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml >$out

      # Replace the section for sdmmc-device with our own section
      cat ${partitionsEmmc} >>$out

      tail -n 2 ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml >>$out
    '';
  in {
    hardware.nvidia-jetpack.flashScriptOverrides = {
      partitionTemplate = partitionTemplate;
      flashArgs = lib.mkForce ["-r" "${config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard}" "mmcblk0p1"];
    };
  };
  image = hostConfiguration.extendModules {
    modules = [
      flashOptions
    ];
  };
  config = image.config;
in
  nixpkgs.legacyPackages.x86_64-linux.stdenvNoCC.mkDerivation {
    src = config.hardware.nvidia-jetpack.flashScript;
    name = "flash-ghaf-host";
    installPhase = ''
      mkdir -p $out/bin
      sed bin/flash-ghaf-host -e "s|chmod -R u+w \.|cp -v ${images}/esp.img bootloader/esp.img\nchmod -R u+w .|" >$out/bin/flash-ghaf-host
      chmod ugo+x $out/bin/flash-ghaf-host
    '';
  }
