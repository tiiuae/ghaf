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

  boot.kernelPatches = [
    {
      name = "passthrough-patch";
      patch = ./pci-passthrough-test.patch;
    }
  ];

  hardware.deviceTree = {
    enable = true;
    name = "tegra234-p3701-host-passthrough.dtb";
  };

  # Passthrough Jetson Orin WiFi card
  boot.kernelParams = [
    "vfio-pci" "ids=10ec:c82f"
    "vfio_iommu_type1.allow_unsafe_interrupts=1"
  ];

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
