# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.givc.appvm;
  policycfg = config.ghaf.givc.policyClient;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    mapAttrs
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  guivmName = "gui-vm";
  appUserUid = toString config.ghaf.users.appUser.uid;
in
{
  _file = ./appvm.nix;

  options.ghaf.givc.appvm = {
    enable = mkEnableOption "Enable appvm givc module.";
    applications = mkOption {
      type = types.listOf types.attrs;
      default = [ { } ];
      description = "Applications to run in the appvm.";
    };
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in appvm.";
      }
    ];
    # Configure appvm service
    givc.appvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit (config.ghaf.users.homedUser) uid;
      network = {
        agent.transport = {
          name = hostName;
          addr = hosts.${hostName}.ipv4;
          port = "9000";
        };
        socketProxy = [
        {
          transport = {
            name = guivmName;
            addr = hosts.${guivmName}.ipv4;
            port = "9030";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_sni.sock";
        }
      ];
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
        tls.enable = config.ghaf.givc.enableTls;
      };
      capabilities = {
        inherit (cfg) applications;

        policy = mkIf policycfg.enable {
          enable = true;
          inherit (policycfg) storePath;
          policies = mapAttrs (_name: value: value.dest) policycfg.policies;
        };
      };
    };
    # SNI renamer: runs on the real session bus, owns org.kde.StatusNotifierWatcher,
    # and acquires dot-based well-known names (org.kde.StatusNotifierItem.proxy_<pid>_<n>)
    # for every SNI app — including apps such as Element and Discord that register
    # with their unique D-Bus name (:1.X) instead of a well-known name.
    # This lets the GIVC tunnel xdg-dbus-proxy run with filter=true and
    # --talk=org.kde.StatusNotifierItem.* (which requires dot-separated names).
    systemd.services.dbus-proxy-sni-renamer = {
      description = "SNI renamer for ${hostName}: bridge unique-name tray apps to well-known names";
      after = [ "dbus.socket" ];
      requires = [ "dbus.socket" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1s";
        User = appUserUid;
        Environment = [
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${appUserUid}/bus"
        ];
        ExecStart = [
          "${lib.getExe pkgs.dbus-proxy} --renamer-mode"
        ];
      };
      startLimitIntervalSec = 0;
      wantedBy = [ "multi-user.target" ];
    };

    givc.dbusproxy = {
      enable = true;
      session = {
        enable = true;
        user = config.ghaf.users.appUser.name;
        socket = "/tmp/dbusproxy_sni.sock";
        policy = {
          own = [ "org.kde.StatusNotifierWatcher" ];
          talk = [
            # Receive StatusNotifierItemRegistered/Unregistered signals from renamer
            "org.kde.StatusNotifierWatcher"
            # Talk to renamer-assigned item names (org.kde.StatusNotifierItem.proxy_*)
            "org.kde.StatusNotifierItem.*"
          ];
        };
      };
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
