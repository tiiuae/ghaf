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
    enable = mkEnableOption "the guivm GIVC module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in guivm.";
      }
    ];

    # Access control rules for gui-vm.
    ghaf.givc.accessControl.adminRules = [
      {
        from = [ config.networking.hostName ];
        permittedRequests = [
          "Suspend"
          "Reboot"
          "Poweroff"
          "SetLocale"
          "SetTimezone"
          "StartService"
          "ListGenerations"
          "SetGeneration"
          "StartVM"
          "Watch"
          "GetStats"
          "QueryList"
          "Sysinfo"
          "PauseApplication"
          "ResumeApplication"
          "StopApplication"
        ];
      }
      # Microvm services for apps, executed by admin
      {
        from = [ config.networking.hostName ];
        to = config.ghaf.common.appHosts;
        permittedRequests = [
          "StartApplication"
        ];
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
            ]
            ++
              lib.optionals
                (
                  builtins.elem audiovmName config.ghaf.common.vms
                  && audioCfg.enable
                  && audioCfg.client.pipewireControl.enable
                )
                [
                  {
                    transport = {
                      name = audiovmName;
                      addr = hosts.${audiovmName}.ipv4;
                      inherit (audioCfg.server.pipewireForwarding) port;
                      protocol = "tcp";
                    };
                    inherit (audioCfg.client.pipewireControl) socket;
                  }
                ];
        };
        eventProxy = {
          enable = true;
          events =
            lib.optionals
              (
                (builtins.elem guivmName config.ghaf.common.vms)
                && (builtins.elem audiovmName config.ghaf.common.vms)
              )
              [
                {
                  transport = {
                    name = guivmName;
                    addr = hosts.${guivmName}.ipv4;
                    port = "9012";
                    protocol = "tcp";
                  };
                  consumer = {
                    enable = true;
                    permittedSource = audiovmName;
                  };
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

    ghaf.givc.guivm.dbusProxies = {
      networkmanager = mkIf (builtins.elem netvmName config.ghaf.common.vms) {
        description = "DBus proxy for Network Manager ${guivmName}";
        busName = "org.freedesktop.NetworkManager";
        objectPath = "/org/freedesktop/NetworkManager";
        socket = "/tmp/dbusproxy_net.sock";
      };
      bluetooth = mkIf (builtins.elem audiovmName config.ghaf.common.vms) {
        description = "DBus proxy for Bluetooth ${guivmName}";
        busName = "org.bluez";
        objectPath = "/org/bluez";
        socket = "/tmp/dbusproxy_snd.sock";
      };
    };
    services.dbus.packages = [
      pkgs.bluez
      pkgs.networkmanager
    ];
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
      "-w /run/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
