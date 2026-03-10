# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  audioCfg = config.ghaf.services.audio;
  cfg = config.ghaf.givc.audiovm;
  inherit (lib)
    mkEnableOption
    mkIf
    optionals
    ;
  guivmName = "gui-vm";
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
in
{
  _file = ./audiovm.nix;

  options.ghaf.givc.audiovm = {
    enable = mkEnableOption "Enable audiovm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure audiovm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      network.agent.transport = {
        name = hostName;
        addr = hosts.${hostName}.ipv4;
        port = "9000";
      };
      network.admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
      network.tls.enable = config.ghaf.givc.enableTls;
      capabilities.services = [
        "poweroff.target"
        "reboot.target"
      ]
      ++ optionals config.ghaf.services.power-manager.vm.enable [
        "suspend.target"
        "systemd-suspend.service"
      ];
      capabilities.socketProxy =
        let
          sockets =
            lib.optionals (builtins.elem guivmName config.ghaf.common.vms) [
              {
                transport = {
                  name = guivmName;
                  addr = hosts.${guivmName}.ipv4;
                  port = "9011";
                  protocol = "tcp";
                };
                socket = "/tmp/dbusproxy_snd.sock";
              }
            ]
            ++ lib.optionals (audioCfg.enable && audioCfg.server.pipewireForwarding.enable) [
              {
                transport = {
                  name = guivmName;
                  addr = hosts.${guivmName}.ipv4;
                  inherit (audioCfg.server.pipewireForwarding) port;
                  protocol = "tcp";
                };
                inherit (audioCfg.server.pipewireForwarding) socket;
              }
            ];
        in
        {
          enable = sockets != [ ];
          inherit sockets;
        };
      capabilities.eventProxy =
        let
          events = lib.optionals (builtins.elem guivmName config.ghaf.common.vms) [
            {
              transport = {
                name = guivmName;
                addr = hosts.${guivmName}.ipv4;
                port = "9012";
                protocol = "tcp";
              };
              producer = true;
              device = "mouse";
            }
          ];
        in
        {
          enable = events != [ ];
          inherit events;
        };
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
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
