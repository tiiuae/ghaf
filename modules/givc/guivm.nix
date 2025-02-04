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
    ;
  netvmName = "net-vm";
  audiovmName = "audio-vm";
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
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
      transport = {
        name = hostName;
        addr = hosts.${hostName}.ipv4;
        port = "9000";
      };
      admin = lib.head config.ghaf.givc.adminConfig.addresses;
      tls.enable = config.ghaf.givc.enableTls;
      enableUserTlsAccess = true;
      socketProxy = [
        {
          transport = {
            name = netvmName;
            addr = hosts.${netvmName}.ipv4;
            port = "9010";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_net.sock";
        }
        {
          transport = {
            name = audiovmName;
            addr = hosts.${audiovmName}.ipv4;
            port = "9011";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_snd.sock";
        }
      ];
    };
  };
}
