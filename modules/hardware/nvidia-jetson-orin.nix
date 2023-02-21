# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{config, ...}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;
  };

  nixpkgs.hostPlatform.system = "aarch64-linux";

  hardware.deviceTree = {
    enable = true;
    name = "tegra234-p3701-0000-p3737-0000.dtb";
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    # TODO: Maybe add store path or some unique identifier to the filename
    extraFiles."dtbs/${config.hardware.deviceTree.name}" = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
    extraInstallCommands = ''
      default_cfg=$(cat /boot/loader/loader.conf | grep default | awk '{print $2}')
      echo "devicetree /dtbs/${config.hardware.deviceTree.name}" >> /boot/loader/entries/$default_cfg
    '';
  };
}
