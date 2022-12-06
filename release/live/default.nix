# SPDX-FileCopyrightText: 2022 Unikie

{ config ? import ../../../spectrum/nix/eval-config.nix {}, hostKernel ? null }:

let
  inherit (config) pkgs;
  spectrum = import ../../../spectrum/release/live { };
  appvm-zathura = pkgs.callPackage ../../vm/zathura { inherit config; };
  usbvm = pkgs.callPackage ../../vm/usb { inherit config; };
  usbappvm = pkgs.callPackage ../../vm/usbapp {inherit config; };

  myextpart = with pkgs; vmTools.runInLinuxVM (
    stdenv.mkDerivation {
      name = "myextpart";
      nativeBuildInputs = [ e2fsprogs util-linux ];
      buildCommand = ''
        ${kmod}/bin/modprobe loop
        ${kmod}/bin/modprobe ext4

        cd /tmp/xchg
        install -m 0644 ${spectrum.EXT_FS} user-ext.ext4
        spaceInMiB=$(du -sB M ${appvm-zathura} | awk '{ print substr( $1, 1, length($1)-1 ) }')
        dd if=/dev/zero bs=1M count=$(expr $spaceInMiB + 50) >> user-ext.ext4
        spaceInMiB=$(du -sB M ${usbvm} | awk '{ print substr( $1, 1, length($1)-1 ) }')
        dd if=/dev/zero bs=1M count=$(expr $spaceInMiB + 50) >> user-ext.ext4
        spaceInMiB=$(du -sB M ${usbappvm} | awk '{ print substr( $1, 1, length($1)-1 ) }')
        dd if=/dev/zero bs=1M count=$(expr $spaceInMiB + 50) >> user-ext.ext4
        resize2fs -p user-ext.ext4

        tune2fs -O ^read-only user-ext.ext4
        mkdir mp
        mount -o loop,rw user-ext.ext4 mp
        tar -C ${appvm-zathura} -c data | tar -C mp/svc -x
        chmod +w mp/svc/data
        tar -C ${usbvm} -c data | tar -C mp/svc -x
        chmod +w mp/svc/data
        tar -C ${usbappvm} -c data | tar -C mp/svc -x
        chmod +w mp/svc/data
        umount mp
        tune2fs -O read-only user-ext.ext4
        cp user-ext.ext4 $out
      '';
    });
in
with pkgs;

spectrum.overrideDerivation (oldAttrs: {
  EXT_FS = myextpart;
  KERNEL = linux_imx8;
  pname = "build/live.img";
  installPhase = ''
    runHook preInstall
    dd if=/dev/zero bs=1M count=6 >> $pname
    partnum=$(sfdisk --json $pname | grep "node" | wc -l)
    while [ $partnum -gt 0 ]; do
      echo '+6M,' | sfdisk --move-data $pname -N $partnum
      partnum=$((partnum-1))
    done
    dd if=${ubootImx8}/flash.bin of=$pname bs=1k seek=32 conv=notrunc
    IMG=$pname
    ESP_OFFSET=$(sfdisk --json $IMG | jq -r '
      # Partition type GUID identifying EFI System Partitions
      def ESP_GUID: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
      .partitiontable |
      .sectorsize * (.partitions[] | select(.type == ESP_GUID) | .start)
    ')
    mcopy -no -i $pname@@$ESP_OFFSET $KERNEL/dtbs/freescale/imx8qm-mek-hdmi.dtb ::/
    mcopy -no -i $pname@@$ESP_OFFSET ${imx-firmware}/hdmitxfw.bin ::/
    mv $pname $out
    runHook postInstall
  '';
})
