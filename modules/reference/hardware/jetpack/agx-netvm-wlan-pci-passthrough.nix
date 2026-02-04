# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
in
{
  options.ghaf.hardware.nvidia.orin.agx.enableNetvmWlanPCIPassthrough =
    lib.mkEnableOption "WLAN or ethernet card PCI passthrough to NetVM";
  config = lib.mkIf cfg.agx.enableNetvmWlanPCIPassthrough {
    # Orin AGX WLAN card PCI passthrough
    ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon = true;

    # Common Wifi Service set

    # Passthrough devices - use hardware.definition for composition model
    ghaf.hardware.definition.netvm.extraModules = [
      {
        ghaf.services.wifi.enable = true;
        # This bus holds the PCI ethernet or WLAN devices on ORIN AGX's
        microvm.devices =
          if cfg.somType == "agx-industrial" then
            [
              {
                bus = "pci";
                path = "0001:01:00.0";
              }
              {
                bus = "pci";
                path = "0000:01:00.0";
              }
            ]
          else
            [
              {
                bus = "pci";
                path = "0001:01:00.0";
              }
            ];
        # Network Manager is defined for netvm of Orin Devices
        environment.systemPackages = [ pkgs.networkmanager ];
        # Network Manager package defines a gnome plugin with build failure on Orin
        networking.networkmanager.plugins = lib.mkForce [ ];
      }
    ];

    hardware.deviceTree.overlays = [
      {
        name = "agx-ethernet-pci-passthough-overlay";
        dtsFile =
          if (cfg.somType == "agx64") then
            ./agx64-ethernet-pci-passthrough-overlay.dts
          else if (cfg.somType == "agx-industrial") then
            ./agx-industrial-ethernet-pci-passthrough-overlay.dts
          else
            ./agx-ethernet-pci-passthrough-overlay.dts;
      }
    ];

    boot.kernelPatches = lib.mkIf (config.ghaf.hardware.nvidia.orin.kernelVersion == "upstream-6-6") [
      {
        name = "vfio-true";
        patch = ./0001-ARM-SMMU-drivers-return-always-true-for-IOMMU_CAP_CA.patch;
      }
    ];

    # The PCI IDs for the onboard Realtek ethernet and wifi cards and the intel ethernet on AGX Industrial
    boot.kernelParams = [
      "vfio-pci.ids=10ec:c822,10ec:c82f,8086:1533"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ];
  };
}
