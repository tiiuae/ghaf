# SPDX-FileCopyrightText: 2022 Unikie

{ config ? import ../../../spectrum/nix/eval-config.nix {} }:

let
  inherit (config) pkgs;
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
        install -m 0644 ${spectrum-live.EXT_FS} user-ext.ext4
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
        chmod +w mp/svc/data
        # A lot of room for improvements
        mkdir mp/svc/data/appvm-zathura && tar -C ${appvm-zathura} -c . | tar -C mp/svc/data/appvm-zathura -x
        mkdir mp/svc/data/usbvm && tar -C ${usbvm} -c . | tar -C mp/svc/data/usbvm -x
        mkdir mp/svc/data/usbappvm && tar -C ${usbappvm} -c . | tar -C mp/svc/data/usbappvm -x
        umount mp
        tune2fs -O read-only user-ext.ext4
        cp user-ext.ext4 $out
      '';
    });
in
with pkgs;

spectrum-live.overrideAttrs (oldAttrs: {
  EXT_FS = myextpart;
  ROOT_FS = spectrum-rootfs;
})
