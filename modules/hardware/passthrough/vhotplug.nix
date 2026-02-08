# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.passthrough.vhotplug;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    getExe
    ;

  defaultVms = lib.attrsets.mapAttrsToList (
    vmName: vmParams:
    let
      vmConfig = lib.ghaf.vm.getConfig vmParams;
    in
    {
      name = vmName;
      type = if vmConfig != null then vmConfig.microvm.hypervisor else "qemu";
      socket = "${config.microvm.stateDir}/${vmName}/${
        if vmConfig != null then vmConfig.microvm.socket else "microvm.sock"
      }";
    }
  ) config.microvm.vms;
in
{
  _file = ./vhotplug.nix;

  options.ghaf.hardware.passthrough.vhotplug = {
    enable = mkEnableOption "Enable hot plugging of USB devices";

    usbRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of USB hot plugging rules.
      '';
    };

    pciRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of PCI hot plugging rules.
      '';
    };

    evdevRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of evdev hot plugging rules.
      '';
    };

    acpiRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of ACPI hot plugging rules.
      '';
    };

    vms = mkOption {
      type = types.listOf types.attrs;
      default = defaultVms;
      description = ''
        List of virtual machines.
      '';
    };

    prependUsbRules = mkOption {
      description = ''
        List of extra USB rules to be added to the system. Uses the same format as vhotplug.usbRules,
        and is prepended to the default rules. This is helpful for setting rules where the order of
        USB device detection matters for additional VMs, while still maintaining the default rules.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    postpendUsbRules = mkOption {
      description = ''
        List of extra USB rules to be added to the system. Uses the same format as vhotplug.usbRules,
        and is postpened to the default rules. This is useful for adding rules for additional VMs while
        keeping the ghaf defaults.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    api = {
      enable = mkOption {
        description = ''
          Enable external API.
        '';
        type = types.bool;
        default = true;
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 2000;
        description = ''
          API port number.
        '';
      };

      transports = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "tcp"
            "unix"
            "vsock"
          ]
        );
        default = [
          "vsock"
          "unix"
        ];
        description = ''
          List of supported transports for the API.
        '';
        example = [
          "tcp"
          "unix"
          "vsock"
        ];
      };

      allowedCids = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default =
          if config.ghaf.networking.hosts ? gui-vm then [ config.ghaf.networking.hosts.gui-vm.cid ] else [ ];
        description = ''
          List of VSOCK CIDs allowed to connect.
        '';
        example = [
          3
          4
          5
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", GROUP="kvm"
      KERNEL=="event*", GROUP="kvm"
      SUBSYSTEM=="vfio",GROUP="kvm"
    '';

    environment.etc."vhotplug.conf".text = builtins.toJSON {
      usbPassthrough = cfg.prependUsbRules ++ cfg.usbRules ++ cfg.postpendUsbRules;
      pciPassthrough = cfg.pciRules;
      evdevPassthrough = cfg.evdevRules;
      acpiPassthrough = cfg.acpiRules;

      inherit (cfg) vms;

      general = {
        api = {
          inherit (cfg.api) enable;
          inherit (cfg.api) port;
          inherit (cfg.api) transports;
          inherit (cfg.api) allowedCids;
          unixSocketUser = "microvm";
        };
        modprobe = lib.getExe' pkgs.kmod "modprobe";
        modinfo = lib.getExe' pkgs.kmod "modinfo";
      };
    };

    systemd.services.vhotplug = {
      enable = true;
      description = "vhotplug";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "microvm@.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${getExe pkgs.vhotplug} -a -c /etc/vhotplug.conf";
      };
      startLimitIntervalSec = 0;
    };

    environment.systemPackages = [ pkgs.vhotplug ];
  };
}
