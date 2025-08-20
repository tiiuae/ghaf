# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  cfg = config.ghaf.hardware.passthrough.secure-hotplug;

  usbHotplugRulesType = types.submodule {
    options = {
      denylist = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        description = ''
          USB devices to blacklist.
          Key is vendor ID (e.g., "0xbadb" or "~0xbabb" for all except this vendor).
          Value is a list of product IDs (e.g., ["0xdada"]).
        '';
        example = {
          "0xbadb" = [ "0xdada" ];
          "~0xbabb" = [ "0xcaca" ];
        };
      };

      allowlist = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        description = ''
          USB devices to whitelist and assign to specific VMs.
          Key is "vendorID:productID" (e.g., "0x0b95:0x1790").
          Value is a list of VM names (e.g., ["net-vm"]).
        '';
        example = {
          "0x0b95:0x1790" = [ "net-vm" ];
        };
      };

      classlist = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        description = ''
          Rules based on USB device class, subclass, and protocol.
          Key is "class:subclass:protocol" (e.g., "0x01:*:*", use "*" for wildcard).
          Value is a list of VM names (e.g., ["audio-vm"]).
        '';
        example = {
          "0x01:*:*" = [ "audio-vm" ];
        };
      };
    };
  };

  # VMs for passthrough
  vmNames = builtins.attrNames config.ghaf.hardware.passthrough.VMs;

  # For a given device name, collect VMs whose permittedDevices include it
  vmsForDevice =
    deviceName:
    builtins.filter (
      vm: builtins.elem deviceName (config.ghaf.hardware.passthrough.VMs.${vm}.permittedDevices or [ ])
    ) vmNames;

  passthroughDevices = builtins.map (
    d: d // { vms = vmsForDevice d.name; }
  ) config.ghaf.hardware.passthrough.usb.devices;
  legacyPassthroughDevices = builtins.map (
    d: d // { vms = vmsForDevice d.name; }
  ) config.ghaf.hardware.definition.usb.devices;
in
{
  options.ghaf.hardware.passthrough.secure-hotplug = {
    enable = mkEnableOption "Enable passthrough daemon";
    usb = {
      hotplugRules = mkOption {
        type = usbHotplugRulesType;
        default = { };
        description = "USB hotplug rule definitions, populated from rulesFile if specified, or can be set directly.";
        example = {
          denylist = {
            "0x1234" = [ "0x5678" ];
          };
          allowlist = {
            "0xabcd:0xef01" = [ "net-vm" ];
          };
          classlist = {
            "0x03:*:*" = [ "gui-vm" ];
          };
          vmdenylist = {
            "chrome-vm" = [ "0x04f2:0xb751" ];
          };
        };
      };
    };
  };

  config =
    mkIf
      (
        config.ghaf.hardware.passthrough.secure-hotplug.enable
        && config.ghaf.hardware.passthrough.mode != "none"
      )
      {
        environment.etc = {
          "hotplug.conf".text = builtins.toJSON {
            usb = {
              hotplug_rules = cfg.usb.hotplugRules;
              static_devices =
                if config.ghaf.hardware.passthrough.mode == "dynamic" then
                  if config.ghaf.hardware.passthrough.usb.devices != [ ] then
                    passthroughDevices
                  else
                    legacyPassthroughDevices
                else
                  [ ];
            };
            eventDevices = {
              inherit (config.ghaf.hardware.passthrough.eventDevices) targetVM;
              inherit (config.ghaf.hardware.passthrough.eventDevices) pcieBusPrefix;
            };
          };
        };

        services.udev.extraRules = ''
          SUBSYSTEM=="usb", GROUP="kvm"
          KERNEL=="event*", GROUP="kvm"
        '';

        systemd.services.secure-hotplug = {
          enable = true;
          description = "vhotplug";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "1";
            ExecStart = "${pkgs.vhotplug}/bin/vhotplug  -a -p /etc/hotplug.conf";
          };
          startLimitIntervalSec = 0;
        };
      };
}
