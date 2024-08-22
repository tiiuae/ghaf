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
    boot.kernelPatches = builtins.trace "kernelPatches GPIO Virtualization" [
      /*
      {
        name = "Added Configurations to Support GPIO passthrough";
        patch = null;
        extraStructuredConfig = {
          PCI_STUB = lib.mkDefault lib.kernel.yes;
          HOTPLUG_PCI = lib.mkDefault lib.kernel.yes;
          HOTPLUG_PCI_ACPI = lib.mkDefault lib.kernel.yes;
          PCI_DEBUG = lib.mkDefault lib.kernel.yes;
          PCI_HOST_GENERIC = lib.mkDefault lib.kernel.yes;
          PCI_HOST_COMMON = lib.mkDefault lib.kernel.yes;
          VFIO = lib.mkDefault lib.kernel.yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault lib.kernel.yes;
          VFIO_PLATFORM = lib.mkDefault lib.kernel.yes;
          VIRTIO = lib.mkDefault lib.kernel.yes;
          VIRTIO_PCI = lib.mkDefault lib.kernel.yes;
          VIRTIO_MMIO = lib.mkDefault lib.kernel.yes;
          GPIO_TEGRA = lib.mkDefault lib.kernel.yes;
          GPIO_TEGRA186 = lib.mkDefault lib.kernel.yes;
          TEGRA_GPIO_HOST_PROXY = lib.mkDefault lib.kernel.no;
          TEGRA_GPIO_GUEST_PROXY = lib.mkDefault lib.kernel.no;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault lib.kernel.no;
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault lib.kernel.no;

          # long version of possibly needed additions for microvm and gpio + some obviously not needed configs
          # most of these are set anyhow, some are unrelated (such as XUSB) but included while debugging
          # virtualisation
          # VFIO_IOMMU_TYPE1 = lib.mkDefault lib.kernel.yes;
          VFIO_PCI_INTX = lib.mkDefault lib.kernel.yes;
          VFIO_PCI_MMAP = lib.mkDefault lib.kernel.yes;
          VFIO_PCI = lib.mkDefault lib.kernel.yes;
          VFIO_VIRQFD = lib.mkDefault lib.kernel.yes;
          VIRTIO_MENU = lib.mkDefault lib.kernel.yes;
          VIRTIO_PCI_LEGACY = lib.mkDefault lib.kernel.yes;
          VIRTUALIZATION = lib.mkDefault lib.kernel.yes;
          # KVM
          KVM_ARM_PMU = lib.mkDefault lib.kernel.yes;
          KVM_GENERIC_DIRTYLOG_READ_PROTECT = lib.mkDefault lib.kernel.yes;
          KVM_MMIO = lib.mkDefault lib.kernel.yes;
          KVM_VFIO = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_ARCH_TLB_FLUSH_ALL = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_CPU_RELAX_INTERCEPT = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_EVENTFD = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_IRQ_BYPASS = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_IRQCHIP = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_IRQFD = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_IRQ_ROUTING = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_MSI = lib.mkDefault lib.kernel.yes;
          HAVE_KVM_VCPU_RUN_PID_CHANGE = lib.mkDefault lib.kernel.yes;
          HAVE_VIRT_CPU_ACCOUNTING_GEN = lib.mkDefault lib.kernel.yes;
          #BPMP
          TEGRA_BPMP = lib.mkDefault lib.kernel.yes;
          CLK_TEGRA_BPMP = lib.mkDefault lib.kernel.yes;
          RESET_TEGRA_BPMP = lib.mkDefault lib.kernel.yes;
          #GPIO -- move gpio related to gpio-virt-host/default.nix ?
          GPIO_GENERIC_PLATFORM = lib.mkDefault lib.kernel.yes;
          GPIO_GENERIC = lib.mkDefault lib.kernel.yes;
          OF_GPIO = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA186 = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA194 = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA210 = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA234 = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA_XUSB = lib.mkDefault lib.kernel.yes;
          PINCTRL_TEGRA = lib.mkDefault lib.kernel.yes;
        };
      }
      */

      # patching the kernel for GPIO passthrough
      {
        name = "GPIO Virtualization";
        patch = builtins.trace "GPIO Virtualization (patch kernel)" ./patches/0003-gpio-virt-kernel.patch;
      }
      # patching the custom GPIO kernel modules
      {
        name = "GPIO Virt Drivers";
        patch = builtins.trace "GPIO Virt Drivers (patch kernel modules)" ./patches/0004-gpio-virt-drivers.patch;
      }
    ];
  };
}
