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
  inherit (lib) mkEnableOption mkIf;
  hostName = "net-vm";
  guivmName = "gui-vm";
  vmEntry = vm: builtins.filter (x: x.name == vm) config.ghaf.networking.hosts.entries;
  address = vm: lib.head (builtins.map (x: x.ip) (vmEntry vm));
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
      agent = {
        name = hostName;
        addr = address hostName;
        port = "9000";
      };
      wifiManager = true;
      hwidService = true;
      tls.enable = config.ghaf.givc.enableTls;
      admin = config.ghaf.givc.adminConfig;
      socketProxy = [
        {
          transport = {
            name = guivmName;
            addr = address guivmName;
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
        user = config.ghaf.users.proxyUser.name;
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
