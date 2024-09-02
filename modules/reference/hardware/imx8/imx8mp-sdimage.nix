# SPDX-FileCopyrightText: 2023-2024 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];

  disabledModules = [ (modulesPath + "/profiles/all-hardware.nix") ];
  sdImage = {
    compressImage = false;

    populateFirmwareCommands = ''
      cp ${pkgs.imx8m-boot}/image/flash.bin firmware/
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';

    postBuildCommands = ''
      sdimage="$out/nixos.img"
      fwoffset=64
      blocksize=512
      fwsize=20400
      rootoffset=20800

      sfdisk --list $img | grep Linux
      rootstart=$(sfdisk --list $img | grep Linux | awk '{print $3}')
      rootsize=$(sfdisk --list $img | grep Linux | awk '{print $5}')
      imagesize=$(((rootoffset + rootsize)*blocksize))
      touch $sdimage
      truncate -s $imagesize  $sdimage
      echo -e "
        label: dos
        label-id: 0x2178694e
        unit: sectors
        sector-size: 512

        start=$fwoffset, size=$fwsize, type=60
        start=$rootoffset, size=$rootsize, type=83, bootable" > "$out/partition.txt"
      sfdisk -d $img
      sfdisk $sdimage < "$out/partition.txt"
      dd conv=notrunc if=${pkgs.imx8m-boot}/image/flash.bin of=$sdimage seek=$fwoffset
      dd conv=notrunc if=$img of=$sdimage seek=$rootoffset skip=$rootstart count=$rootsize
      sfdisk --list $sdimage
      rm -rf $out/sd-image
    '';
  };
}
