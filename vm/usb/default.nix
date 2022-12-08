# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2022 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

{ config ? import ../../../spectrum/nix/eval-config.nix {}
, terminfo ? config.pkgs.foot.terminfo
}:

config.pkgs.pkgsStatic.callPackage (

{ lib, stdenvNoCC, runCommand, writeReferencesToFile, buildPackages
, jq, s6-rc, tar2ext4, util-linux, xorg
, busybox, connmanMinimal, dbus, execline, kmod, mdevd, nftables, s6
, s6-linux-init, usbutils, socat
}:

let
  inherit (lib) cleanSource cleanSourceWith concatMapStringsSep hasSuffix;

  scripts = import ../../../spectrum/scripts { inherit config; };

  connman = connmanMinimal;

  packages = [
    connman dbus execline kmod mdevd s6 s6-linux-init s6-rc socat usbutils

    (busybox.override {
      extraConfig = ''
        CONFIG_DEPMOD n
        CONFIG_INSMOD n
        CONFIG_LSMOD n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_RMMOD n
        CONFIG_LSUSB n 
      '';
    })

    (nftables.override { withCli = false; })
  ];

  packagesSysroot = runCommand "packages-sysroot" {
    inherit packages;
    nativeBuildInputs = [ xorg.lndir ];
    passAsFile = [ "packages" ];
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1
    ln -s ${concatMapStringsSep " " (p: "${p}/bin/*") packages} $out/usr/bin
    ln -s ${kernel}/lib "$out"
    ln -s ${terminfo}/share/terminfo $out/usr/share

    for pkg in ${dbus} ${connman}; do
        lndir -silent $pkg/share/dbus-1 $out/usr/share/dbus-1
    done
  '';

  packagesTar = runCommand "packages.tar" {} ''
    cd ${packagesSysroot}
    tar -cf $out --verbatim-files-from \
        -T ${writeReferencesToFile packagesSysroot} .
  '';

  kernel = buildPackages.linux.override {
    structuredExtraConfig = with lib.kernel; {
      EFI_STUB=yes;
      EFI=yes;
      VIRTIO = yes;
      VIRTIO_PCI = yes;
      VIRTIO_BLK = yes;
      VIRTIO_CONSOLE = yes;
      EXT4_FS = yes;
      DRM_BOCHS = yes;
      DRM = yes;
      AGP = yes;
      VSOCKETS = yes;
      VSOCKETS_DIAG = yes;
      VSOCKETS_LOOPBACK = yes;
      VIRTIO_VSOCKETS = module;
      VIRTIO_VSOCKETS_COMMON = yes;
      VSOCKMON = yes;
      VHOST_VSOCK = yes;
      USBIP_CORE = module ;
      USBIP_VHCI_HCD = module;
      USBIP_HOST = module;
      USBIP_VUDC = module;
    };
  };
in

stdenvNoCC.mkDerivation {
  name = "appvm-usb";

  src = cleanSourceWith {
    filter = name: _type:
      name != "${toString ./.}/build" &&
      !(hasSuffix ".nix" name);
    src = cleanSource ./.;
  };

  nativeBuildInputs = [ jq s6-rc tar2ext4 util-linux ];

  PACKAGES_TAR = packagesTar;
  VMLINUX = "${kernel.dev}/vmlinux";

  makeFlags = [ "SCRIPTS=${scripts}" ];

  installPhase = ''
    mv build/svc $out
  '';

  enableParallelBuilding = true;

  passthru = { inherit kernel; };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}
