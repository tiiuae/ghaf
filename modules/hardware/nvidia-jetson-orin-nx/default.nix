# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson AGX Orin
{
  lib,
  config,
  ...
}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-nx";
    carrierBoard = "devkit";
    modesetting.enable = true;

    flashScriptOverrides = {
      #flashArgs = lib.mkForce ["-r" "${config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard}" "mmcblk0p1"];
      flashArgs = lib.mkForce ["-r" "${config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard}" "nvme0n1p1"];
    };
  };

  nixpkgs.hostPlatform.system = "aarch64-linux";

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  ghaf.boot.loader.systemd-boot-dtb.enable = true;

  boot.kernelPatches = [
    {
      name = "passthrough-patch";
      patch = ./pci-passthrough-test.patch;
    }
    {
      name = "vsock-config";
      patch = null;
      extraStructuredConfig = with lib.kernel; {
        VHOST = yes;
        VHOST_MENU = yes;
        VHOST_IOTLB = yes;
        VHOST_VSOCK = yes;
        VSOCKETS = yes;
        VSOCKETS_DIAG = yes;
        VSOCKETS_LOOPBACK = yes;
        VIRTIO_VSOCKETS_COMMON = yes;
      };
    }
  ];

  hardware.deviceTree = {
    enable = true;
    # Redifining the board as Jetson Orin NX with the Jetson-IO-base-B
    # here the Orin NX 16GB is p3767-0000 and Jetson IO base-B is p3509-a02
    ##name = "tegra234-p3767-0000-p3509-a02.dtb";
    name = "tegra234-p3767-host-passthrough.dtb";
  };

  imports = [
    ../../boot/systemd-boot-dtb.nix

    ./partition-template.nix
  ];

  # Passthrough Jetson Orin WiFi card
  boot.kernelParams = [
    "vfio-pci.ids=10ec:8168"
    "vfio_iommu_type1.allow_unsafe_interrupts=1"
  ];
}
