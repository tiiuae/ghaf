# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mkIf
    literalExpression
    ;
  cfg = config.ghaf.hardware.passthrough.pciPorts;
  qemuPciPorts =
    portCount:
    builtins.concatMap (n: [
      "-device"
      "pcie-root-port,bus=pcie.0,id=${cfg.pcieBusPrefix}${toString n},chassis=${toString n}"
    ]) (lib.range 1 portCount);

  # Default number of ports for PCI hotplugging in VMs
  pciPortDefaults = {
    # GUIVM requires multiple ports for evdev passthrough (touchpad, keyboard, etc.)
    "gui-vm" = (lib.length config.ghaf.hardware.definition.gpu.pciDevices) + 7;
    # NetVM only needs ports for a PCIe Wi-Fi adapter or NIC
    "net-vm" = (lib.length config.ghaf.hardware.definition.network.pciDevices) + 2;
    # Audio controllers often include multiple devices in the same IOMMU group
    "audio-vm" = (lib.length config.ghaf.hardware.definition.audio.pciDevices) + 7;
  };
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

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {
    ghaf.hardware.passthrough.qemuExtraArgs = lib.mapAttrs (
      _vmName: qemuPciPorts
    ) cfg.pciePortCountForVMs;
  };
}
