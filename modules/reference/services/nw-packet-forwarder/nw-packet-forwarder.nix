# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    optionalString
    ;
  cfg = config.services.nw-packet-forwarder;

  chromecastVmIpAddr = config.ghaf.networking.hosts.${cfg.chromecast.vmName}.ipv4;
  chromecastVmMac = config.ghaf.networking.hosts.${cfg.chromecast.vmName}.mac;
  netVmInternalIp = config.ghaf.networking.hosts."net-vm".ipv4;
  chromecastFlags = optionalString cfg.chromecast.enable ''
    --ccastvm-mac ${chromecastVmMac} \
    --ccastvm-ip ${chromecastVmIpAddr}/24
  '';
  nw-pckt-fwd-launcher = pkgs.writeShellScriptBin "nw-pckt-fwd" ''
    ${pkgs.ghaf-nw-packet-forwarder}/bin/nw-pckt-fwd \
    --external-iface ${cfg.externalNic} \
    --internal-iface ${cfg.internalNic} \
    --internal-ip ${cfg.internalIp} ${chromecastFlags}
  '';
in
{
  _file = ./nw-packet-forwarder.nix;

  options.services.nw-packet-forwarder = {
    enable = mkEnableOption "nw-packet-forwarder";
    confFile = mkOption {
      type = types.path;
      example = "/var/lib/nw-packet-forwarder/nw-packet-forwarder.conf";
      description = ''
        Ignore all other nw-packet-forwarder options and load configuration from this file.
      '';
    };

    externalNic = mkOption {
      type = types.str;
      default = "";
      example = "";
      description = ''
        External NIC
      '';
    };

    internalNic = mkOption {
      type = types.str;
      default = "";
      example = "";
      description = ''
        Internal NIC
      '';
    };

    internalIp = mkOption {
      type = types.str;
      default = netVmInternalIp;
      example = "";
      description = ''
        Internal IP
      '';
    };
    chromecast = mkOption {
      description = "nw-packet-forwarder chromecast configuration";
      type = types.submodule {
        options = {
          enable = mkEnableOption "Enable chromecast feature";

          vmName = mkOption {
            type = types.str;
            example = "chrome-vm";
            description = "The name of the chromium/chrome VM to setup chromecast for.";
            default = "chrome-vm";
          };
        };
      };
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.externalNic != "";
        message = "External Nic must be set";
      }
      {
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
    ];

    services.nw-packet-forwarder.confFile = lib.mkDefault (
      pkgs.writeText "nw-packet-forwarder.conf" ''
        # TODO: create config file if there are a lot of cli parameters
      ''
    );

    systemd.services."nw-packet-forwarder" = {
      description = "Network packet forwarder daemon";

      bindsTo = [
        "sys-subsystem-net-devices-${cfg.externalNic}.device"
        "sys-subsystem-net-devices-${cfg.internalNic}.device"
      ];
      after = [
        "sys-subsystem-net-devices-${cfg.externalNic}.device"
        "sys-subsystem-net-devices-${cfg.internalNic}.device"
      ];

      wantedBy = [
        "multi-user.target"
        "sys-subsystem-net-devices-${cfg.externalNic}.device"
        "sys-subsystem-net-devices-${cfg.internalNic}.device"
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${nw-pckt-fwd-launcher}/bin/nw-pckt-fwd";
        Restart = "always";
        RestartSec = "15s";
      };
    };

  };

}
