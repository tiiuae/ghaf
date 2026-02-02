# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.nx;
  ethPciDevice = "0008:01:00.0";
in
{
  options.ghaf.hardware.nvidia.orin.nx.enableNetvmEthernetPCIPassthrough =
    lib.mkEnableOption "Ethernet card PCI passthrough to NetVM";
  config = lib.mkIf cfg.enableNetvmEthernetPCIPassthrough {
    # Orin NX Ethernet card PCI Passthrough
    ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon = true;

    # Wait up to 60 seconds for ethernet PCI to get enumerated
    systemd.services."microvm-pci-devices@net-vm".serviceConfig.ExecStartPre = ''
      ${pkgs.bash}/bin/bash -c ' \
      TIMEOUT=60; \
      ELAPSED=0; \
      while [ ! -e /sys/bus/pci/devices/${ethPciDevice} ]; do \
        if [ $ELAPSED -ge $TIMEOUT ]; then \
          echo "Timeout reached: PCI device ${ethPciDevice} did not appear after $TIMEOUT seconds."; \
          exit 1; \
        fi; \
        echo "Waiting for PCI device ${ethPciDevice}... $ELAPSED/$TIMEOUT seconds"; \
        sleep 1; \
        ELAPSED=$((ELAPSED + 1)); \
      done; \
      echo "PCI device ${ethPciDevice} is present."'
    '';

    ghaf.virtualization.microvm.extensions.netvm = [
      {
        microvm.devices = [
          {
            bus = "pci";
            path = ethPciDevice;
          }
        ];
      }
    ];

    hardware.deviceTree.overlays = [
      {
        name = "nx-ethernet-pci-passthough-overlay";
        dtsFile = ./nx-ethernet-pci-passthough-overlay.dts;
      }
    ];

    boot.kernelPatches = lib.mkIf (config.ghaf.hardware.nvidia.orin.kernelVersion == "upstream-6-6") [
      {
        name = "vfio-true";
        patch = ./0001-ARM-SMMU-drivers-return-always-true-for-IOMMU_CAP_CA.patch;
      }
    ];

    boot.kernelParams = [
      "vfio-pci.ids=10ec:8168"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ];
  };
}
