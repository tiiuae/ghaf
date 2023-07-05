{
  config,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  sdImage = {
    compressImage = false;
    populateFirmwareCommands = ''
      cp ${pkgs.uboot-icicle-kit}/payload.bin firmware/
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
    postBuildCommands = ''
      sdimage="$out/nixos.img"
      blocksize=512
      offset=34
      ubootsize=2048
      sfdisk --list $img | grep Linux
      rootstart=$(sfdisk --list $img | grep Linux | awk '{print $3}')
      rootsize=$(sfdisk --list $img | grep Linux | awk '{print $5}')
      imagesize=$(((offset + ubootsize + rootsize + 2048)*blocksize))
      touch $sdimage
      truncate -s $imagesize  $sdimage

      echo -e "
         label: gpt
         label-id: 47D1675F-84FF-41C5-9CBD-CC6D822159EC
         unit: sectors
         first-lba: $offset
         last-lba: $((ubootsize + offset + $rootsize - 1))
         sector-size: 512

         start=$offset, size=$ubootsize, type=21686148-6449-6E6F-744E-656564454649, uuid=0F5E6BEA-86F5-4936-8712-6DBF3B46B2A0, name=\"uboot\"
         start=$((offset + ubootsize)), size=$rootsize, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=17E58027-1F0E-4146-8F88-AB26C740BC6D, name=\"kernel\", attrs=\"LegacyBIOSBootable\" " > "$out/partition.txt"

      sfdisk $sdimage < "$out/partition.txt"
      dd conv=notrunc if=${pkgs.uboot-icicle-kit}/payload.bin of=$sdimage seek=$offset
      dd conv=notrunc if=$img of=$sdimage seek=$((offset + ubootsize)) skip=$rootstart count=$rootsize
      sfdisk --list $sdimage
      rm -rf $out/sd-image
    '';
  };
}
