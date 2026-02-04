# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  pkgs,
  options,
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

  # Check if hardware.definition option exists
  hasHardwareDefinition = options ? ghaf.hardware.definition;

  defaultGuivmPciRules =
    optionals hasHardwareDefinition [
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
    optionals hasHardwareDefinition [
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
    optionals hasHardwareDefinition [
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
    ++ optionals cfg.autoDetectAudio [
      {
        description = "Auto-detected Devices for AudioVM";
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
  hwDetectModule = vm: [
    {
      microvm.extraArgsScript = "${lib.getExe' pkgs.vhotplug "vhotplugcli"} vmm args --vm ${vm} --qemu-bus-prefix ${busPrefix}";
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

    autoDetectGpu = mkOption {
      description = ''
        Auto-detect GPU PCI devices.
      '';
      type = types.bool;
      default = false;
    };

    autoDetectNet = mkOption {
      description = ''
        Auto-detect network PCI devices.
      '';
      type = types.bool;
      default = false;
    };

    autoDetectAudio = mkOption {
      description = ''
        Auto-detect audio PCI devices.
      '';
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") (
    {
      ghaf.hardware.passthrough.vhotplug.pciRules =
        optionals config.ghaf.virtualization.microvm.guivm.enable cfg.guivmRules
        ++ optionals config.ghaf.virtualization.microvm.netvm.enable cfg.netvmRules
        ++ optionals config.ghaf.virtualization.microvm.audiovm.enable cfg.audiovmRules;

      # ACPI rules are host-side vhotplug config (not VM extraModules)
      # They pass the NHLT ACPI table needed for microphone arrays
      ghaf.hardware.passthrough.vhotplug.acpiRules = optionals cfg.autoDetectAudio audiovmAcpiRules;

      ghaf.virtualization.microvm.netvm.extraModules = optionals cfg.autoDetectNet (
        hwDetectModule "net-vm"
      );
    }
    # Auto-detected config goes via hardware definition (only available on x86 with hardware definition)
    // lib.optionalAttrs hasHardwareDefinition {
      ghaf.hardware.definition.guivm.extraModules = optionals cfg.autoDetectGpu (hwDetectModule "gui-vm");
      ghaf.hardware.definition.audiovm.extraModules = optionals cfg.autoDetectAudio (
        hwDetectModule "audio-vm"
      );
    }
  );
}
