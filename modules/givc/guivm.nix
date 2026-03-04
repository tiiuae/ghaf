# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  audioCfg = config.ghaf.services.audio;
  cfg = config.ghaf.givc.guivm;
  policycfg = config.ghaf.givc.policyClient;
  inherit (lib)
    mapAttrs
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
  _file = ./guivm.nix;

  options.ghaf.givc.guivm = {
    enable = mkEnableOption "Enable guivm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in guivm.";
      }
    ];

    # Configure guivm service
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      enableUserTlsAccess = true;
      notifier.enable = true;
      network = {
        agent.transport = {
          name = hostName;
          addr = hosts.${hostName}.ipv4;
          port = "9000";
        };
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
        tls.enable = config.ghaf.givc.enableTls;
      };
      capabilities = {
        services = [
          "reboot.target"
          "poweroff.target"
        ];
        socketProxy = {
          enable = true;
          sockets =
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
              (lib.optionalAttrs (audioCfg.enable && audioCfg.client.pipewireControl.enable) {
                transport = {
                  name = audiovmName;
                  addr = hosts.${audiovmName}.ipv4;
                  inherit (audioCfg.server.pipewireForwarding) port;
                  protocol = "tcp";
                };
                inherit (audioCfg.client.pipewireControl) socket;
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
              producer = false;
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
    systemd.services.dbus-proxy-networkmanager = {
      description = "DBus proxy for Network Manager ${guivmName}";
      # Wait for GIVC to create the socket before starting
      after = [ "givc-${guivmName}.service" ];
      requires = [ "givc-${guivmName}.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1s";
        # Wait up to 30 seconds for the socket to appear
        ExecStartPre = [
          "${pkgs.coreutils}/bin/timeout 30 ${pkgs.bash}/bin/bash -c 'until [ -S /tmp/dbusproxy_net.sock ]; do sleep 0.5; done'"
        ];
        Environment = [
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock"
          "NM_SECRET_AGENT_XML=${pkgs.networkmanager}/share/dbus-1/interfaces/org.freedesktop.NetworkManager.SecretAgent.xml"
        ];
        ExecStart = [
          ''
            ${lib.getExe pkgs.dbus-proxy} \
              --source-bus-name org.freedesktop.NetworkManager \
              --source-object-path /org/freedesktop/NetworkManager \
              --proxy-bus-name org.freedesktop.NetworkManager \
              --source-bus-type session \
              --target-bus-type system \
              --nm-mode
          ''
        ];
      };
      startLimitIntervalSec = 0;
      wantedBy = [ "multi-user.target" ];
    };
    services.dbus.packages = [ pkgs.networkmanager ];
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
      "-w /run/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
