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
  guivmName = "gui-vm";
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
      services = [
        "reboot.target"
        "poweroff.target"
      ];
      admin = lib.head config.ghaf.givc.adminConfig.addresses;
      tls.enable = config.ghaf.givc.enableTls;
      enableUserTlsAccess = true;
      socketProxy =
        lib.optionals (builtins.elem netvmName config.ghaf.common.vms) [
          {
            transport = {
              name = netvmName;
              addr = hosts.${netvmName}.ipv4;
              port = "9010";
              protocol = "tcp";
            };
            socket = "/tmp/dbusproxy_net.sock";
          }
        ]
        ++ lib.optionals (builtins.elem audiovmName config.ghaf.common.vms) [
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
      eventProxy = [
        {
          transport = {
            name = guivmName;
            addr = hosts.${guivmName}.ipv4;
            port = "9012";
            protocol = "tcp";
          };
          producer = false;
        }
      ];
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
      "-w /run/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
