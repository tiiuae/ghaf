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
    imap1
    getExe
    mkOption
    mkForce
    optionals
    optionalString
    types
    mkIf
    ;

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

in
{
  options.ghaf.hardware.devices = {

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
      nics = mkIf (!config.ghaf.hardware.usb.vhotplug.enable) {
        microvm.devices = imap1 (i: d: {
          bus = "pci";
          path = pciPath d;
          qemu.deviceExtraArgs =
            optionalString (d.qemu.deviceExtraArgs != null) d.qemu.deviceExtraArgs + "id=pci-${toString i}";
        }) nicPciDevices;

        services.udev.extraRules = concatMapStringsSep "\n" (
          d:
          ''SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${d.vendorId}", ATTRS{device}=="0x${d.productId}", NAME="${d.name}"''
        ) nicPciDevices;
      };

      gpus.microvm.devices = mkForce (
        imap1 (i: d: {
          bus = "pci";
          path = pciPath d;
          qemu.deviceExtraArgs =
            optionalString (d.qemu.deviceExtraArgs != null) d.qemu.deviceExtraArgs + "id=pci-${toString i}";
        }) gpuPciDevices
      );

      audio.microvm.devices = optionals (!config.ghaf.hardware.usb.vhotplug.enable) (
        imap1 (i: d: {
          bus = "pci";
          path = pciPath d;
          qemu.deviceExtraArgs =
            optionalString (d.qemu.deviceExtraArgs != null) d.qemu.deviceExtraArgs + "id=pci-${toString i}";
        }) sndPciDevices
      );

      evdev.microvm.qemu.extraArgs = lib.concatLists (
        lib.imap1 (i: d: [
          "-device"
          "virtio-input-host-pci,evdev=${d},id=evdev-${toString i}"
        ]) evdevDevices
      );
    };
  };
}
