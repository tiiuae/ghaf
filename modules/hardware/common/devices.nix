# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    flatten
    imap1
    getExe
    mkOption
    mkForce
    optionals
    optionalString
    types
    ;

  cfg = config.ghaf.hardware.devices;

  # Function to determine the PCI device path if not provided
  # based on vendorId and productId
  pciPath =
    d:
    if (d.path == "") then
      let
        findPciPathScript = pkgs.writeShellApplication {
          name = "find-pci-path";
          runtimeInputs = [
            pkgs.pciutils
            pkgs.gnugrep
            pkgs.coreutils
          ];
          text = ''
            PCI_PATH=$(lspci -Dnn | grep "${d.vendorId}:${d.productId}" | cut -c 1-12 | head -n 1)
            if [ -z "$PCI_PATH" ]; then
              echo "Error: PCI device ${d.vendorId}:${d.productId} not found." >&2
              exit 1
            fi
            echo "$PCI_PATH"
          '';
        };
      in
      "$(${getExe findPciPathScript})"
    else
      d.path;

  # Shorthand substitutions
  nicPciDevices = config.ghaf.hardware.definition.network.pciDevices;
  gpuPciDevices = config.ghaf.hardware.definition.gpu.pciDevices;
  sndPciDevices = config.ghaf.hardware.definition.audio.pciDevices;
  evdevDevices = config.ghaf.hardware.definition.input.misc.evdev;

  # Offsets for the PCI root ports
  nicPortOffset = config.ghaf.hardware.usb.vhotplug.pciePortCount;
  gpuPortOffset = nicPortOffset + (lib.length nicPciDevices);
  sndPortOffset = gpuPortOffset + (lib.length gpuPciDevices);

in
{
  options.ghaf.hardware.devices = {

    hotplug = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable hotplugging of PCI devices. This allows to dynamically add or remove
        PCI devices to the microvm without needing to restart it. Useful for power
        management and future use cases.
      '';
    };
    nics = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        NIC PCI devices to passthrough.
      '';
    };
    gpus = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        GPU PCI devices to passthrough.
      '';
    };
    audio = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Audio PCI devices to passthrough.
      '';
    };
    evdev = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Evdev devices to passthrough.
      '';
    };
  };

  config = {

    ghaf.hardware.devices = {
      nics = {
        microvm.qemu.extraArgs = optionals cfg.hotplug (
          flatten (
            imap1 (i: _d: [
              "-device"
              "pcie-root-port,id=pci_hotplug_${toString (i + nicPortOffset)},bus=pcie.0,chassis=${toString (i + nicPortOffset)}"
            ]) nicPciDevices
          )
        );

        microvm.devices = mkForce (
          imap1 (i: d: {
            bus = "pci";
            path = pciPath d;
            qemu.deviceExtraArgs =
              optionalString (d.qemu.deviceExtraArgs != null) (
                d.qemu.deviceExtraArgs + optionalString cfg.hotplug ","
              )
              + optionalString cfg.hotplug "id=pci${toString (i + nicPortOffset)},bus=pci_hotplug_${toString (i + nicPortOffset)}";
          }) nicPciDevices
        );

        services.udev.extraRules = concatMapStringsSep "\n" (
          d:
          ''SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${d.vendorId}", ATTRS{device}=="0x${d.productId}", NAME="${d.name}"''
        ) nicPciDevices;
      };

      gpus = {
        microvm.qemu.extraArgs = optionals cfg.hotplug (
          flatten (
            imap1 (i: _d: [
              "-device"
              "pcie-root-port,id=pci_hotplug_${toString (i + gpuPortOffset)},bus=pcie.0,chassis=${toString (i + gpuPortOffset)}"
            ]) gpuPciDevices
          )
        );

        microvm.devices = mkForce (
          imap1 (i: d: {
            bus = "pci";
            path = pciPath d;
            qemu.deviceExtraArgs =
              optionalString (d.qemu.deviceExtraArgs != null) (
                d.qemu.deviceExtraArgs + optionalString cfg.hotplug ","
              )
              + optionalString cfg.hotplug "id=pci${toString (i + gpuPortOffset)},bus=pci_hotplug_${toString (i + gpuPortOffset)}";
          }) gpuPciDevices
        );
      };

      audio = {
        microvm.qemu.extraArgs = optionals cfg.hotplug (
          flatten (
            imap1 (i: _d: [
              "-device"
              "pcie-root-port,id=pci_hotplug_${toString (i + sndPortOffset)},bus=pcie.0,chassis=${toString (i + sndPortOffset)}"
            ]) sndPciDevices
          )
        );

        microvm.devices = mkForce (
          imap1 (i: d: {
            bus = "pci";
            path = pciPath d;
            qemu.deviceExtraArgs =
              optionalString (d.qemu.deviceExtraArgs != null) (
                d.qemu.deviceExtraArgs + optionalString cfg.hotplug ","
              )
              + optionalString cfg.hotplug "id=pci${toString (i + sndPortOffset)},bus=pci_hotplug_${toString (i + sndPortOffset)}";
          }) sndPciDevices
        );
      };

      evdev = {
        microvm.qemu.extraArgs = builtins.concatMap (d: [
          "-device"
          "virtio-input-host-pci,evdev=${d}"
        ]) evdevDevices;
      };
    };
  };
}
