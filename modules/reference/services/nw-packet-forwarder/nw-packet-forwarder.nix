# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nw-packet-forwarder;
  nw-packet-forwarder = pkgs.callPackage ../../../../packages/nw-packet-forwarder { };

  chromevmIpAddr = config.ghaf.networking.hosts."chrome-vm".ipv4;
  chromevmMac = config.ghaf.networking.hosts."chrome-vm".mac;
  netVmInternalIp = config.ghaf.networking.hosts."net-vm".ipv4;

  nwPcktFwdUser = "nwpcktfwd-admin";
in
{
  options.services.nw-packet-forwarder = {
    enable = lib.mkEnableOption "nw-packet-forwarder";
    confFile = lib.mkOption {
      type = lib.types.path;
      example = "/var/lib/nw-packet-forwarder/nw-packet-forwarder.conf";
      description = ''
        Ignore all other nw-packet-forwarder options and load configuration from this file.
      '';
    };

    externalNic = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "";
      description = ''
        External NIC
      '';
    };

    internalNic = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "";
      description = ''
        Internal NIC
      '';
    };

    internalIp = lib.mkOption {
      type = lib.types.str;
      default = netVmInternalIp;
      example = "";
      description = ''
        Internal IP
      '';
    };
    chromecast = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable chromecast feature
      '';
    };

  };
  config = lib.mkIf cfg.enable {
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

    # Define a new group for proxy management
    users.groups.${nwPcktFwdUser} = { }; # Create a group named proxy-admin

    # Define a new user with a specific username
    users.users.${nwPcktFwdUser} = {
      isSystemUser = true;
      description = "Network Packet forwarder system user";
      group = "${nwPcktFwdUser}";
    };

    # Allow proxy-admin group to manage specific systemd services without a password
    security = {
      polkit = {
        enable = true;
        debug = true;
        # Polkit rules for allowing proxy-user to run proxy related systemctl
        # commands without sudo and password requirement
        extraConfig = ''
          polkit.addRule(function(action, subject) {
               if (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") == "nw-packet-forwarder.service" &&
              subject.user == "${nwPcktFwdUser}") {
                  return polkit.Result.YES;
              }
          });
        '';
      };

    };

    services.nw-packet-forwarder.confFile = lib.mkDefault (
      pkgs.writeText "nw-packet-forwarder.conf" ''

      ''
    );

    systemd.services."nw-packet-forwarder" = {
      description = "Network packet forwarder daemon";
      #  bindsTo = [ "sys-subsystem-net-devices-${cfg.bindingNic}.device" ];
      #  after = [ "sys-subsystem-net-devices-${cfg.bindingNic}.device" ];
      wantedBy = [ "multi-user.target" ];
      #after = [ "network.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ghaf-nw-packet-forwarder}/bin/nw-pckt-fwd --external-iface ${cfg.externalNic} --internal-iface ${cfg.internalNic} --internal-ip ${cfg.internalIp} --chromecast=${toString cfg.chromecast} --chromevm-mac ${chromevmMac} --chromevm-ip ${chromevmIpAddr}/24";
        User = "${nwPcktFwdUser}";
        # Restart the service if it fails
        Restart = "on-failure";
        # Wait 5s before restarting.
        RestartSec = "5s";
        AmbientCapabilities = "CAP_NET_RAW CAP_NET_ADMIN";
        CapabilityBoundingSet = "CAP_NET_RAW CAP_NET_ADMIN";
        # PrivateTmp = true;
        # PrivateDevices = true;
        ProtectHome = true;
        # NoNewPrivileges=true;
        ProtectControlGroups = true;
        ProtectSystem = "full";
      };
    };

  };

}
