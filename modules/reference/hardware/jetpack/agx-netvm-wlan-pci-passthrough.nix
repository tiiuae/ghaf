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
  _file = ./agx-netvm-wlan-pci-passthrough.nix;

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
                crosvm.guestAddress = "00:01.0";
              }
            ];
        # Network Manager is defined for netvm of Orin Devices
        environment.systemPackages = [ pkgs.networkmanager ];
        # Network Manager package defines a gnome plugin with build failure on Orin
        networking.networkmanager.plugins = lib.mkForce [ ];
      }
    ];

    systemd.services."microvm@net-vm".after = [ "unbindPcieRootport.service" ];
    systemd.services.unbindPcieRootport = {
      description = "Unbind PCIe root port to release IOMMU group";
      wantedBy = [ "multi-user.target" ];
      script = ''
        echo 0001:00:00.0 > /sys/bus/pci/devices/0001:00:00.0/driver/unbind || true
        echo 1 > /sys/bus/platform/devices/14100000.pcie/dma_cleanup || true
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
      };
    };

    boot.kernelPatches = lib.mkIf (config.ghaf.hardware.nvidia.orin.kernelVersion == "upstream-6-6") [
      {
        name = "vfio-true";
        patch = ./0001-ARM-SMMU-drivers-return-always-true-for-IOMMU_CAP_CA.patch;
      }
      {
        name = "Realtek Wifi Drivers";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          RTW88 = module;
          RTW88_8822CE = module;
          RTW88_DEBUG = yes;
          RTW88_DEBUGFS = yes;
        };
      }
    ];

    # The PCI IDs for the onboard Realtek ethernet and wifi cards and the intel ethernet on AGX Industrial
    boot.kernelParams = [
      "vfio-pci.ids=10ec:c822,10ec:c82f,8086:1533"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
    ]
    ++ lib.optionals config.ghaf.host.kernel.hardening.hypervisor.enable [
      "pkvm.assign_permissive=1"
      "kvm-arm.hyp_iommu_pages=86016"
    ];
  };
}
