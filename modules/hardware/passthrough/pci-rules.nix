# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mkIf
    optionals
    ;

  cfg = config.ghaf.hardware.passthrough.pci;

  defaultGuivmPciRules =
    optionals (builtins.hasAttr "definition" config.ghaf.hardware) [
      {
        description = "Static PCI Devices for GUIVM";
        targetVm = "gui-vm";
        skipOnSuspend = true;
        allow = map (d: {
          address = d.path;
          deviceId = d.productId;
          inherit (d) vendorId;
        }) config.ghaf.hardware.definition.gpu.pciDevices;
      }
    ]
    ++ optionals cfg.autoDetectPci [
      {
        description = "Dynamic PCI Devices for GUIVM";
        targetVm = "gui-vm";
        skipOnSuspend = true;
        pciIommuAddAll = true;
        allow = [
          {
            deviceClass = 3;
            description = "Display Devices";
          }
        ];
      }
    ];

  defaultNetvmPciRules =
    optionals (builtins.hasAttr "definition" config.ghaf.hardware) [
      {
        description = "Static PCI Devices for NetVM";
        targetVm = "net-vm";
        allow = map (d: {
          address = d.path;
          deviceId = d.productId;
          inherit (d) vendorId;
        }) config.ghaf.hardware.definition.network.pciDevices

        ;
      }
    ]
    ++ optionals cfg.autoDetectPci [
      {
        description = "Dynamic PCI Devices for NetVM";
        targetVm = "net-vm";
        pciIommuSkipIfShared = true;
        allow = [
          {
            deviceClass = 2;
            description = "Network Devices";
          }
        ];
      }
    ];

  defaultAudiovmPciRules =
    optionals (builtins.hasAttr "definition" config.ghaf.hardware) [
      {
        description = "PCI Devices for AudioVM";
        targetVm = "audio-vm";
        allow = map (d: {
          address = d.path;
          deviceId = d.productId;
          inherit (d) vendorId;
        }) config.ghaf.hardware.definition.audio.pciDevices;
      }
    ]
    ++ optionals cfg.autoDetectPci [
      {
        description = "Dynamic Devices for AudioVM";
        targetVm = "audio-vm";
        pciIommuAddAll = true;
        allow = [
          {
            deviceClass = 4;
            deviceSubclass = 3;
            description = "Audio Devices";
          }
        ];
      }
    ];

in
{
  options.ghaf.hardware.passthrough.pci = {

    guivmRules = mkOption {
      description = "PCI Device Passthrough Rules for GUIVM";
      type = types.listOf types.attrs;
      default = defaultGuivmPciRules;
    };

    netvmRules = mkOption {
      description = "PCI Device Passthrough Rules for NetVM";
      type = types.listOf types.attrs;
      default = defaultNetvmPciRules;
    };

    audiovmRules = mkOption {
      description = "PCI Device Passthrough Rules for AudioVM";
      type = types.listOf types.attrs;
      default = defaultAudiovmPciRules;
    };

    autoDetectPci = mkOption {
      description = ''
        Auto-detect PCI devices.
      '';
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {

    ghaf.hardware.passthrough.vhotplug.pciRules =
      optionals config.ghaf.virtualization.microvm.guivm.enable cfg.guivmRules
      ++ optionals config.ghaf.virtualization.microvm.netvm.enable cfg.netvmRules
      ++ optionals config.ghaf.virtualization.microvm.audiovm.enable cfg.audiovmRules;

  };
}
