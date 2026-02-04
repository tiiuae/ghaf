# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.hardware.nvidia.virtualization;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.virtualization.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable virtualization support for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by modules that need it. Manually enabling this option is not recommended in
      release builds.
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPatches = [
      {
        name = "Added Configurations to Support Vda";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
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
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault no;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault no;
        };
      }
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      # {
      #   name = "Bpmp Support Virtualization";
      #   patch = ./patches/0003-bpmp-support-bpmp-virt.patch;
      # }
      # {
      #   name = "Bpmp Virt Drivers";
      #   patch = ./patches/0004-bpmp-virt-drivers-5-15.patch;
      # }
      # {
      #   name = "Bpmp Overlay";
      #   patch = ./patches/0005-bpmp-overlay.patch;
      # }
    ];

    boot.kernelParams = [ "vfio_iommu_type1.allow_unsafe_interrupts=1" ];
  };
}
