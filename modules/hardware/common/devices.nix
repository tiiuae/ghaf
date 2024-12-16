# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkOption types mkForce;
in
{
  options.ghaf.hardware.devices = {
    netvmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        PCI devices to passthrough to the netvm.
      '';
    };
    guivmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        PCI devices to passthrough to the guivm.
      '';
    };
    audiovmPCIPassthroughModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        PCI devices to passthrough to the audiovm.
      '';
    };
    guivmVirtioInputHostEvdevModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Virtio evdev paths' to passthrough to the guivm.
      '';
    };
  };

  config = {
    ghaf.hardware.devices = {
      netvmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          }) config.ghaf.hardware.definition.network.pciDevices
        );
        ghaf.hardware.definition.network.pciDevices = config.ghaf.hardware.definition.network.pciDevices;
      };

      guivmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          }) config.ghaf.hardware.definition.gpu.pciDevices
        );
        ghaf.hardware.definition.gpu.pciDevices = config.ghaf.hardware.definition.gpu.pciDevices;
      };

      audiovmPCIPassthroughModule = {
        microvm.devices = mkForce (
          builtins.map (d: {
            bus = "pci";
            inherit (d) path;
          }) config.ghaf.hardware.definition.audio.pciDevices
        );
        ghaf.hardware.definition.audio.pciDevices = config.ghaf.hardware.definition.audio.pciDevices;
      };

      guivmVirtioInputHostEvdevModule = {
        microvm.qemu.extraArgs =
          builtins.concatMap
            (d: [
              "-device"
              "virtio-input-host-pci,evdev=${d}"
            ])
            (
              config.ghaf.hardware.definition.input.keyboard.evdev
              ++ config.ghaf.hardware.definition.input.mouse.evdev
              ++ config.ghaf.hardware.definition.input.touchpad.evdev
              ++ config.ghaf.hardware.definition.input.misc.evdev
            );
      };
    };
  };
}
