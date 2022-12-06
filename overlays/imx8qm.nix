
final: prev: {
  linux_imx8 = final.callPackage ./bsp/kernel/linux-imx8 { pkgs = final; };
  inherit ( final.callPackage ./bsp/u-boot/imx8qm/imx-uboot.nix { pkgs = final; }) ubootImx8 imx-firmware;
}
