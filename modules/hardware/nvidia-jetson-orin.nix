{pkgs, ...}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;
  };
}
