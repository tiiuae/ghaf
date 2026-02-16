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
  policycfg = config.ghaf.givc.policyClient;
  inherit (lib)
    mapAttrs
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
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in audiovm.";
      }
    ];
    # Configure audiovm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      network = {
        agent.transport = {
          name = hostName;
          addr = hosts.${hostName}.ipv4;
          port = "9000";
        };
        tls.enable = config.ghaf.givc.enableTls;
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
      };
      capabilities = {
        services = [
          "poweroff.target"
          "reboot.target"
        ]
        ++ optionals config.ghaf.services.power-manager.vm.enable [
          "suspend.target"
          "systemd-suspend.service"
        ];
        socketProxy = {
          enable = true;
          sockets = lib.optionals (builtins.elem guivmName config.ghaf.common.vms) [
            {
              transport = {
                name = guivmName;
                addr = hosts.${guivmName}.ipv4;
                port = "9011";
                protocol = "tcp";
              };
              socket = "/tmp/dbusproxy_snd.sock";
            }
            (lib.optionalAttrs (audioCfg.enable && audioCfg.server.pipewireForwarding.enable) {
              transport = {
                name = guivmName;
                addr = hosts.${guivmName}.ipv4;
                inherit (audioCfg.server.pipewireForwarding) port;
                protocol = "tcp";
              };
              inherit (audioCfg.server.pipewireForwarding) socket;
            })
          ];
        };
        eventProxy = {
          enable = true;
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
        };
        policy = mkIf policycfg.enable {
          enable = true;
          inherit (policycfg) storePath;
          policies = mapAttrs (_name: value: value.dest) policycfg.policies;
        };
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
