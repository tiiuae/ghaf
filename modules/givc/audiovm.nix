# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.audiovm;
  inherit (lib) mkEnableOption mkIf;
  hostName = "audio-vm";
  guivmName = "gui-vm";
  vmEntry = vm: builtins.filter (x: x.name == vm) config.ghaf.networking.hosts.entries;
  address = vm: lib.head (builtins.map (x: x.ip) (vmEntry vm));
in
{
  options.ghaf.givc.audiovm = {
    enable = mkEnableOption "Enable audiovm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure audiovm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      agent = {
        name = hostName;
        addr = address hostName;
        port = "9000";
      };
      tls.enable = config.ghaf.givc.enableTls;
      admin = config.ghaf.givc.adminConfig;
      socketProxy = [
        {
          transport = {
            name = guivmName;
            addr = address guivmName;
            port = "9011";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_snd.sock";
        }
      ];
    };
    givc.dbusproxy = {
      enable = true;
      system = {
        enable = true;
        user = config.ghaf.users.proxyUser.name;
        socket = "/tmp/dbusproxy_snd.sock";
        policy = {
          talk = [
            "org.bluez.*"
            "org.blueman.Mechanism.*"
          ];
        };
      };
    };
  };
}
