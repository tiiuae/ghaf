# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# PCI Hardware Passthrough Rules
#
# This module defines PCI passthrough rules and uses the extensions
# registry to add hardware detection to VMs.
#
{
  config,
  lib,
  pkgs,
  ...
}:
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
    ++ optionals cfg.autoDetectGpu [
      {
        description = "Auto-detected PCI Devices for GUIVM";
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
        }) config.ghaf.hardware.definition.network.pciDevices;
      }
    ]
    ++ optionals cfg.autoDetectNet [
      {
        description = "Auto-detected PCI Devices for NetVM";
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
        description = "Static PCI Devices for AudioVM";
        targetVm = "audio-vm";
        allow = map (d: {
          address = d.path;
          deviceId = d.productId;
          inherit (d) vendorId;
        }) config.ghaf.hardware.definition.audio.pciDevices;
      }
    ]
    ++ optionals cfg.autoDetectAudio [
      {
        description = "Auto-detected PCI Devices for AudioVM";
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

  # ACPI NHLT table passthrough is required for the microphone array on some devices
  audiovmAcpiRules = [
    {
      description = "NHLT ACPI Table for AudioVM";
      targetVm = "audio-vm";
      allow = [
        {
          acpiTable = "/sys/firmware/acpi/tables/NHLT";
          setUser = "microvm";
        }
      ];
    }
  ];

  busPrefix = config.ghaf.hardware.passthrough.pciPorts.pcieBusPrefix;

  # Hardware detection module for auto-detect features
  hwDetectModule = vm: {
    microvm.extraArgsScript = "${lib.getExe' pkgs.vhotplug "vhotplugcli"} vmm args --vm ${vm} --qemu-bus-prefix ${busPrefix}";
  };

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

    autoDetectGpu = mkOption {
      description = "Auto-detect GPU PCI devices.";
      type = types.bool;
      default = false;
    };

    autoDetectNet = mkOption {
      description = "Auto-detect network PCI devices.";
      type = types.bool;
      default = false;
    };

    autoDetectAudio = mkOption {
      description = "Auto-detect audio PCI devices.";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {

    ghaf.hardware.passthrough.vhotplug.pciRules =
      optionals config.ghaf.virtualization.microvm.guivm.enable cfg.guivmRules
      ++ optionals config.ghaf.virtualization.microvm.netvm.enable cfg.netvmRules
      ++ optionals config.ghaf.virtualization.microvm.audiovm.enable cfg.audiovmRules;

    ghaf.hardware.passthrough.vhotplug.acpiRules = optionals cfg.autoDetectAudio audiovmAcpiRules;

    # Use extensions registry for hardware detection modules
    ghaf.virtualization.microvm.extensions = {
      guivm = optionals cfg.autoDetectGpu [ (hwDetectModule "gui-vm") ];
      netvm = optionals cfg.autoDetectNet [ (hwDetectModule "net-vm") ];
      audiovm = optionals cfg.autoDetectAudio [ (hwDetectModule "audio-vm") ];
    };
  };
}
