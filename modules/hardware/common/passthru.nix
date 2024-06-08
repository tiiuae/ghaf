# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types mkForce;

  # PCI device passthroughs for vfio
  filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
  mapPciIdsToString = builtins.map (d: "${d.vendorId}:${d.productId}");
  vfioPciIds = mapPciIdsToString (filterDevices (
    config.ghaf.hardware.definition.network.pciDevices
    ++ config.ghaf.hardware.definition.gpu.pciDevices
    ++ config.ghaf.hardware.definition.audio.pciDevices
  ));
in {
  options.ghaf.hardware.passthrough = {
    netvmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        PCI devices to passthrough to the netvm.
      '';
    };
    guivmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        PCI devices to passthrough to the guivm.
      '';
    };
    audiovmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        PCI devices to passthrough to the audiovm.
      '';
    };
    guivmVirtioInputHostEvdevModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        Virtio evdev paths' to passthrough to the guivm.
      '';
    };
    guivmQemuExtraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Extra arguments to pass to qemu when enabling the guivm.
      '';
    };
  };

  config = {
    ghaf.hardware.passthrough = {
      netvmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          })
          config.ghaf.hardware.definition.network.pciDevices
        );
      };

      guivmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          })
          config.ghaf.hardware.definition.gpu.pciDevices
        );
      };

      audiovmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          })
          config.ghaf.hardware.definition.audio.pciDevices
        );
      };

      guivmVirtioInputHostEvdevModule = {
        microvm.qemu.extraArgs =
          builtins.concatMap (d: [
            "-device"
            "virtio-input-host-pci,evdev=${d}"
          ])
          (config.ghaf.hardware.definition.input.keyboard.evdev
            ++ config.ghaf.hardware.definition.input.mouse.evdev
            ++ config.ghaf.hardware.definition.input.touchpad.evdev
            ++ config.ghaf.hardware.definition.input.misc.evdev);
      };

      guivmQemuExtraArgs = [
        # Button
        "-device"
        "button"
        # Battery
        "-device"
        "battery"
        # AC adapter
        "-device"
        "acad"
      ];
    };

    # Enable VFIO for PCI devices
    boot = {
      kernelParams = [
        "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}"
      ];
    };
  };
}
