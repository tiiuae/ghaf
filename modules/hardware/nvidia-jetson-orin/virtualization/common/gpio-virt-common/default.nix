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
      {
        name = "Added Configurations to Support GPIO passthrough";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          PCI_STUB = lib.mkDefault yes;
          HOTPLUG_PCI = lib.mkDefault yes;
          HOTPLUG_PCI_ACPI = lib.mkDefault yes;
          PCI_DEBUG = lib.mkDefault yes;
          PCI_HOST_GENERIC = lib.mkDefault yes;
          PCI_HOST_COMMON = lib.mkDefault yes;
          VFIO = lib.mkDefault yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault yes;
          VFIO_PLATFORM = lib.mkDefault yes;
          VIRTIO_PCI = lib.mkDefault yes;
          VIRTIO_MMIO = lib.mkDefault yes;
          CONFIG_GPIO_TEGRA = lib.mkDefault yes;
          CONFIG_GPIO_TEGRA186 = lib.mkDefault yes;
          TEGRA_GPIO_GUEST_PROXY = lib.mkDefault no;
          TEGRA_GPIO_HOST_PROXY = lib.mkDefault no;
        };
      }
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      {
        name = "GPIO Support Virtualization";
        patch = ./patches/dummy.patch;
      }
      {
        name = "GPIO Virt Drivers";
        patch = ./patches/dummy.patch;
      }
      {
        name = "GPIO Overlay";
        patch = ./patches/dummy.patch;
      }
    ];

    boot.kernelParams = ["iommu=pt :vfio.enable_unsafe_noiommu_mode=0 vfio_iommu_type1.allow_unsafe_interrupts=1 vfio_platform.reset_required=0"];
  };
}
