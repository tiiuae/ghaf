# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;
  };

  nixpkgs.hostPlatform.system = "aarch64-linux";

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  ghaf.boot.loader.systemd-boot-dtb.enable = true;

  hardware.deviceTree = {
    enable = true;
    name = "tegra234-p3701-0000-p3737-0000.dtb";
  };

  imports = [
    ../boot/systemd-boot-dtb.nix
  ];
}
