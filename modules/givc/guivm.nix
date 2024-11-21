# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.guivm;
  inherit (lib) mkEnableOption mkIf;
  hostName = "gui-vm";
  netvmName = "net-vm";
  audiovmName = "audio-vm";
  vmEntry = vm: builtins.filter (x: x.name == vm) config.ghaf.networking.hosts.entries;
  address = vm: lib.head (builtins.map (x: x.ip) (vmEntry vm));
in
{
  options.ghaf.givc.guivm = {
    enable = mkEnableOption "Enable guivm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure guivm service
    givc.sysvm = {
      enable = true;
      agent = {
        name = hostName;
        addr = address hostName;
        port = "9000";
      };
      inherit (config.ghaf.givc) debug;
      tls.enable = config.ghaf.givc.enableTls;
      admin = config.ghaf.givc.adminConfig;
      socketProxy = [
        {
          transport = {
            name = netvmName;
            addr = address netvmName;
            port = "9010";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_net.sock";
        }
        {
          transport = {
            name = audiovmName;
            addr = address audiovmName;
            port = "9011";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_snd.sock";
        }
      ];
    };
  };
}
