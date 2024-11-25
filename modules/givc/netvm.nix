# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.netvm;
  inherit (lib)
    mkEnableOption
    mkIf
    head
    filter
    strings
    ;
  getIp =
    name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.entries));
  admin = head (filter (x: strings.hasInfix ".100." x.addr) config.ghaf.givc.adminConfig.addresses);
  guivmName = "gui-vm";
in
{
  options.ghaf.givc.netvm = {
    enable = mkEnableOption "Enable netvm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure netvm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit admin;
      agent = {
        name = config.networking.hostName;
        addr = getIp config.networking.hostName;
        port = "9000";
      };
      wifiManager = true;
      hwidService = true;
      tls.enable = config.ghaf.givc.enableTls;
      socketProxy = [
        {
          transport = {
            name = guivmName;
            addr = getIp guivmName;
            port = "9010";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_net.sock";
        }
      ];
    };

    givc.dbusproxy = {
      enable = true;
      system = {
        enable = true;
        # TODO Change this with new user setup
        user = "ghaf";
        socket = "/tmp/dbusproxy_net.sock";
        policy = {
          own = [
            "org.freedesktop.NetworkManager.*"
          ];
        };
      };
    };
  };
}
