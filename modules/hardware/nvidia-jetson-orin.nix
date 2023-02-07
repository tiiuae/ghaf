{
  pkgs,
  lib,
  ...
}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;
  };

  # TODO: rpfilter module missing from kernel
  networking.firewall.enable = false;

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
}
