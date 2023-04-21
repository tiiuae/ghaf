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
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;

    flashScriptOverrides = {
      flashArgs = lib.mkForce ["-r" "${config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard}" "mmcblk0p1"];
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
    name = "tegra234-p3701-host-passthrough.dtb";
  };

  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;

  imports = [
    ../../boot/systemd-boot-dtb.nix

    ./partition-template.nix
  ];

  # Passthrough Jetson Orin WiFi card
  boot.kernelParams = [
    "vfio-pci.ids=10ec:c82f,10de:1cb1,10de:0fb9"
    "vfio_iommu_type1.allow_unsafe_interrupts=1"
  ];
}
