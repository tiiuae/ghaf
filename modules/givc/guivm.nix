# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc.guivm;
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
  netvmName = "net-vm";
  audiovmName = "audio-vm";
in
{
  options.ghaf.givc.guivm = {
    enable = mkEnableOption "Enable guivm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure guivm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit admin;
      agent = {
        name = config.networking.hostName;
        addr = getIp config.networking.hostName;
        port = "9000";
      };
      tls.enable = config.ghaf.givc.enableTls;
      enableUserTlsAccess = config.ghaf.givc.enableTls;
      socketProxy = [
        {
          transport = {
            name = netvmName;
            addr = getIp netvmName;
            port = "9010";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_net.sock";
        }
        {
          transport = {
            name = audiovmName;
            addr = getIp audiovmName;
            port = "9011";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_snd.sock";
        }
      ];
    };
  };
}
