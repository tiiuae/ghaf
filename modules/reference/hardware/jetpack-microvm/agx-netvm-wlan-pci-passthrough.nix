# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.agx;
in
{
  options.ghaf.hardware.nvidia.orin.agx.enableNetvmWlanPCIPassthrough =
    lib.mkEnableOption "WLAN card PCI passthrough to NetVM";
  config = lib.mkIf cfg.enableNetvmWlanPCIPassthrough {
    # Orin AGX WLAN card PCI passthrough
    ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon = true;

    # Common Wifi Service set

    # Passthrough devices
    ghaf.virtualization.microvm.netvm.extraModules = [
      {
        ghaf.services.wifi.enable = true;
        microvm.devices = [
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

    boot.kernelPatches = [
      # {
      #   name = "agx-pci-passthrough-patch";
      #   patch = ./pci-passthrough-agx-test.patch;
      # }
    ];

    boot.kernelParams = [
      "vfio-pci.ids=10ec:c82f"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ];

    hardware.deviceTree = {
      enable = true;
      name = "tegra234-p3701-host-passthrough.dtb";
    };
  };
}
