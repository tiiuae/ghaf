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
    mkEnableOption
    mkOption
    types
    mkIf
    optionals
    ;

  cfg = config.ghaf.hardware.passthrough.pci;

  # Check if hardware.definition option exists
  hasHardwareDefinition = options ? ghaf.hardware.definition;

  isIntelIntegratedGpu =
    device:
    device.path == "0000:00:02.0" && device.vendorId != null && lib.toLower device.vendorId == "8086";

  isIntelGscProxy =
    device:
    device.path == "0000:00:16.0" && device.vendorId != null && lib.toLower device.vendorId == "8086";

  isIntelGuiRootBusDevice = device: isIntelIntegratedGpu device || isIntelGscProxy device;

  hasIntelIntegratedGpu =
    hasHardwareDefinition
    && lib.any isIntelIntegratedGpu config.ghaf.hardware.definition.gpu.pciDevices;

  hasIntelGscProxy =
    hasHardwareDefinition && lib.any isIntelGscProxy config.ghaf.hardware.definition.gpu.pciDevices;

  guiVmConfig = config.ghaf.virtualization.vmConfig.sysvms.guivm or { };
  guiVmVmm =
    if (guiVmConfig.vmm or null) != null then
      guiVmConfig.vmm
    else
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm;

  defaultGuivmPciRules =
    optionals hasHardwareDefinition (
      map (d: {
        description = "Static PCI Device ${d.path} for GUIVM";
        targetVm = "gui-vm";
        skipOnSuspend = true;
        # Intel integrated graphics must remain on the guest PCI root bus for
        # IGD OpRegion and GSC proxy discovery. Keep the per-device override
        # for other hardware that has the same Crosvm requirement.
        crosvmUseRootBus = d.crosvm.useRootBus || isIntelGuiRootBusDevice d;
        allow = [
          {
            address = d.path;
            deviceId = d.productId;
            inherit (d) vendorId;
          }
        ];
      }) config.ghaf.hardware.definition.gpu.pciDevices
    )
    ++ optionals cfg.autoDetectGpu [
      {
        description = "Auto-detected PCI Devices for GUIVM";
        targetVm = "gui-vm";
        skipOnSuspend = true;
        pciIommuAddAll = true;
        autoOvmf = true;
        qemuUseRootBus = true;
        crosvmUseRootBus = true;
        allow = [
          {
            deviceClass = 3;
            description = "Display Devices";
          }
        ];
      }
    ]
    ++
      optionals
        (guiVmVmm == "crosvm" && !hasIntelGscProxy && (cfg.autoDetectGpu || hasIntelIntegratedGpu))
        [
          {
            description = "Intel GSC proxy CSME HECI for GUIVM";
            targetVm = "gui-vm";
            skipOnSuspend = true;
            crosvmUseRootBus = true;
            allow = [
              {
                # Intel exposes the CSME HECI endpoint used by the graphics GSC
                # proxy at this stable PCI function across supported laptops.
                address = "0000:00:16.0";
              }
            ];
          }
        ];

  defaultNetvmPciRules =
    optionals hasHardwareDefinition [
      {
        description = "Static PCI Devices for NetVM";
        targetVm = "net-vm";
        tag = "net";
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
        tag = "net";
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
        tag = "audio";
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
        tag = "audio";
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
      microvm.extraArgsScript = "${lib.getExe' pkgs.vhotplug "vhotplugcli"} vmm args --vm ${vm} --qemu-bus-prefix ${busPrefix} --qemu-bus-start-index 1";
    }
  ];

in
{
  _file = ./pci-rules.nix;

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

    autoDetectGpu = mkEnableOption "auto-detection of GPU PCI devices";

    autoDetectNet = mkEnableOption "auto-detection of network PCI devices";

    autoDetectAudio = mkEnableOption "auto-detection of audio PCI devices";
  };

  config = lib.mkMerge [
    (mkIf (config.ghaf.hardware.passthrough.mode != "none") {
      ghaf.hardware.passthrough.vhotplug.pciRules =
        optionals config.ghaf.virtualization.microvm.guivm.enable cfg.guivmRules
        ++ optionals config.ghaf.virtualization.microvm.netvm.enable cfg.netvmRules
        ++ optionals config.ghaf.virtualization.microvm.audiovm.enable cfg.audiovmRules;

      # ACPI rules are host-side vhotplug config (not VM extraModules)
      # They pass the NHLT ACPI table needed for microphone arrays
      ghaf.hardware.passthrough.vhotplug.acpiRules = optionals cfg.autoDetectAudio audiovmAcpiRules;
    })
    # Auto-detected config goes via hardware definition (only available on x86 with hardware definition)
    (mkIf (config.ghaf.hardware.passthrough.mode != "none" && hasHardwareDefinition) {
      ghaf.hardware.definition = {
        guivm.extraModules = optionals cfg.autoDetectGpu (hwDetectModule "gui-vm");
        audiovm.extraModules = optionals cfg.autoDetectAudio (hwDetectModule "audio-vm");
        netvm.extraModules = optionals cfg.autoDetectNet (hwDetectModule "net-vm");
      };
    })
  ];
}
