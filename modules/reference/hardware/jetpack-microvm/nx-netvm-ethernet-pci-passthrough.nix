# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.hardware.nvidia.orin.nx;
in
{
  options.ghaf.hardware.nvidia.orin.nx.enableNetvmEthernetPCIPassthrough = lib.mkEnableOption "Ethernet card PCI passthrough to NetVM";
  config = lib.mkIf cfg.enableNetvmEthernetPCIPassthrough {
    # Orin NX Ethernet card PCI Passthrough
    ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon = true;

    ghaf.virtualization.microvm.netvm.extraModules = [
      {
        microvm.devices = [
          {
            bus = "pci";
            path = "0008:01:00.0";
          }
        ];
        microvm.kernelParams = [
          "pci=nomsi"
          "pcie_acs_override=downstream,multifunction"
        ];
      }
    ];

    boot.kernelPatches = [
      # TODO: Re-enable if still needed with jetson 36.3 + upstream linux
      # {
      #   name = "nx-pci-passthrough-patch";
      #   # This patch uses Alex Williamson's patch for enabling overrides for missing ACS capabilities on pci
      #   # bus which could be accessed from following link: https://lkml.org/lkml/2013/5/30/513
      #   patch = ./pci-passthrough-nx-test.patch;
      # }
    ];

    boot.kernelParams = [
      "vfio-pci.ids=10ec:8168"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ];

    hardware.deviceTree = {
      enable = true;
      name = "tegra234-p3767-host-passthrough.dtb";
    };
  };
}
