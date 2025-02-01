# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.hardware.nvidia.orin.nx;
in
{
  options.ghaf.hardware.nvidia.orin.nx.enableNetvmEthernetPCIPassthrough =
    lib.mkEnableOption "Ethernet card PCI passthrough to NetVM";
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
        # Add 8 seconds delay to wait for PCI devices to get full enumerated
        microvm.preStart = "/bin/sh -c 'sleep 8'";
      }
    ];

    hardware.deviceTree.overlays = [
      {
        name = "nx-ethernet-pci-passthough-overlay";
        dtsFile = ./nx-ethernet-pci-passthough-overlay.dts;
      }
    ];

    boot.kernelParams = [
      "vfio-pci.ids=10ec:8168"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ];
  };
}
