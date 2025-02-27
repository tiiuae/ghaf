# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  kernelVersion = config.boot.kernelPackages.kernel.version;
  cfg = config.ghaf.hardware.nvidia.virtualization;
in
{
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
        name = "Added Configurations to Support VFIO";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          VFIO = lib.mkDefault yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault yes;
          VFIO_PLATFORM = lib.mkDefault yes;
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault no;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault no;
        };
      }
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      (
        if lib.versionAtLeast kernelVersion "6.6" then
          {
            name = "Add bpmp-virt modules";
            patch = ./patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-6.6.patch;
          }
        else if lib.versions.majorMinor kernelVersion == "5.15" then
          {
            name = "Add bpmp-virt modules";
            patch = ./patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch;
          }
        else
          null
      )
      {
        # This patch allows all BPMP (clocks, reset, and power) domains to be accessed
        # by the virtual machine. This is required if not all domains are defined in
        # the host device tree. After the passthrough is working, the required domains
        # should be defined in the host device tree and this patch should be commented.
        name = "Bpmp-host: allows all domains";
        patch = ./patches/0002-Bpmp-host-allows-all-domains.patch;
      }
    ];

    boot.kernelParams = [
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
      "arm-smmu.disable_bypass=0"
    ];
  };
}
