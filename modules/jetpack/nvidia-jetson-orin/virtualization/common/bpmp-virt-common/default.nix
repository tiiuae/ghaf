# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.virtualization;
in {
  config = lib.mkIf cfg.enable {
    boot.kernelPatches = [
      /* configure kernel in modules/hardware/nvidia-jetson-orin/virtualization/default.nix for all virtualisation
      {
        name = "Added Configurations to Support Vda";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          PCI_STUB = lib.mkDefault yes;
          VFIO = lib.mkDefault yes;
          VIRTIO_PCI = lib.mkDefault yes;
          VIRTIO_MMIO = lib.mkDefault yes;
          HOTPLUG_PCI = lib.mkDefault yes;
          PCI_DEBUG = lib.mkDefault yes;
          PCI_HOST_GENERIC = lib.mkDefault yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault yes;
          HOTPLUG_PCI_ACPI = lib.mkDefault yes;
          PCI_HOST_COMMON = lib.mkDefault yes;
          VFIO_PLATFORM = lib.mkDefault yes;
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault yes;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault yes;
        };
      }
      */
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      {
        name = "Bpmp Support Virtualization";
        patch = ./patches/0003-bpmp-support-bpmp-virt.patch;
      }
      {
        name = "Bpmp Virt Drivers";
        patch = ./patches/0004-bpmp-virt-drivers.patch;
      }
      {
        name = "Bpmp Overlay";
        patch = ./patches/0005-bpmp-overlay.patch;
      }
    ];

    boot.kernelParams = ["vfio_iommu_type1.allow_unsafe_interrupts=1"];
  };
}
