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
    types
    optionalAttrs
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
  nicPciDevices = lib.filter (
    d: d.path != "" || (d.vendorId != null && d.productId != null)
  ) config.ghaf.hardware.definition.network.pciDevices;
  gpuPciDevices = config.ghaf.hardware.definition.gpu.pciDevices;
  sndPciDevices = config.ghaf.hardware.definition.audio.pciDevices;
  evdevDevices = config.ghaf.hardware.definition.input.misc.evdev;
  busPrefix = config.ghaf.hardware.passthrough.pciPorts.pcieBusPrefix;
in
{
  _file = ./devices.nix;

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
        microvm.devices = imap1 (i: d: {
          bus = "pci";
          path = pciPath d;
          qemu = {
            inherit (d.qemu) deviceExtraArgs;
          }
          // optionalAttrs cfg.hotplug {
            id = "pci${toString i}";
            bus = "${busPrefix}${toString i}";
          };
        }) nicPciDevices;

        services.udev.extraRules = concatMapStringsSep "\n" (
          d:
          ''SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${d.vendorId}", ATTRS{device}=="0x${d.productId}", NAME="${d.name}"''
        ) nicPciDevices;
      };

      gpus.microvm.devices = imap1 (i: d: {
        bus = "pci";
        path = pciPath d;
        qemu = {
          inherit (d.qemu) deviceExtraArgs;
        }
        // optionalAttrs cfg.hotplug {
          id = "pci${toString i}";
          bus = "${busPrefix}${toString i}";
        };
      }) gpuPciDevices;

      audio.microvm.devices = imap1 (i: d: {
        bus = "pci";
        path = pciPath d;
        qemu = {
          inherit (d.qemu) deviceExtraArgs;
        }
        // optionalAttrs cfg.hotplug {
          id = "pci${toString i}";
          bus = "${busPrefix}${toString i}";
        };
      }) sndPciDevices;

      evdev.microvm.qemu.extraArgs = lib.concatLists (
        lib.imap1 (i: d: [
          "-device"
          "virtio-input-host-pci,evdev=${d},id=evdev-${toString i}"
        ]) evdevDevices
      );
    };
  };
}
