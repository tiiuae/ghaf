# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mkIf
    literalExpression
    ;
  cfg = config.ghaf.hardware.passthrough.pciPorts;

  # Check if hardware.definition option exists
  hasHardwareDefinition = options ? ghaf.hardware.definition;

  # Helper function to get the count of PCI devices from hardware definitions
  staticPciCount =
    dev:
    if hasHardwareDefinition then lib.length config.ghaf.hardware.definition.${dev}.pciDevices else 0;

  # Default number of ports for PCI hotplugging in VMs
  pciPortDefaults = {
    # GUIVM requires multiple ports for evdev passthrough (touchpad, keyboard, etc.)
    "gui-vm" = staticPciCount "gpu" + 7;
    # NetVM only needs ports for a PCIe Wi-Fi adapter or NIC
    "net-vm" = staticPciCount "network" + 2;
    # Audio controllers often include multiple devices in the same IOMMU group
    "audio-vm" = staticPciCount "audio" + 7;
  };

  # Helper function to create PCIe root ports in a microvm
  mkPcieRootPorts =
    vmName:
    map (i: {
      id = "${cfg.pcieBusPrefix}${toString i}";
      chassis = i;
    }) (lib.range 1 cfg.pciePortCountForVMs.${vmName});

in
{
  options.ghaf.hardware.passthrough.pciPorts = {

    pcieBusPrefix = mkOption {
      type = types.nullOr types.str;
      default = "pci_hotplug_";
      description = ''
        PCIe bus prefix used for the pcie-root-port QEMU device.
      '';
    };

    pciePortCountForVMs = lib.mkOption {
      type = types.attrsOf types.int;
      default = pciPortDefaults;
      description = ''
        The number of PCIe ports used for hot-plugging PCI devices to virtual machines.

        In order to support hot-plugging of PCIe devices, QEMU virtual machines must have available PCIe ports created
        by adding pcie-root-port devices at startup. This is used, for example, to pass input devices to the GUI VM as
        virtio-input-host-pci and to passthrough PCI devices from the host (GPU, network, audio devices) as vfio-pci.
        Additionally, vhotplug can detect PCI devices that are not listed in the static hardware definitions and pass
        them through as well.
      '';
      example = literalExpression ''
        {
          "vm-name1" = 5;
          "vm-name2" = 3;
        }
      '';
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") (
    {
      ghaf.virtualization.microvm.netvm.extraModules = [
        {
          microvm.qemu.pcieRootPorts = mkPcieRootPorts "net-vm";
        }
      ];
      ghaf.virtualization.microvm.audiovm.extraModules = [
        {
          microvm.qemu.pcieRootPorts = mkPcieRootPorts "audio-vm";
        }
      ];
    }
    # PCIe root ports config for GUI VM goes via hardware definition (only on x86)
    // lib.optionalAttrs hasHardwareDefinition {
      ghaf.hardware.definition.guivm.extraModules = [
        {
          microvm.qemu.pcieRootPorts = mkPcieRootPorts "gui-vm";
        }
      ];
    }
  );
}
