# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.logging.client;
  listenerAddress = "admin-vm-debug";
  listenerPort = config.ghaf.logging.listener.port;
  sshCommand = "${pkgs.sshpass}/bin/sshpass -p ghaf ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no ghaf@net-vm";
  MacCommand = "cat /sys/class/net/wlp0s5f0/address";
in {
  config = lib.mkIf cfg.enable {
    # TODO: Remove ssh way of MAC retrieval and replace with givc method later
    systemd.services."hw-mac" = {
      description = "Retrieve MAC address from net-vm";
      wantedBy = ["alloy.service"];
      requires = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        # Make sure we can ssh before we retrieve mac address
        ExecStartPre = "${sshCommand} ls";
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c "echo -n $(${sshCommand} ${MacCommand}) > /var/lib/private/alloy/MACAddress"
        '';
      };
    };

    environment.systemPackages = [pkgs.grafana-alloy];

    environment.etc."alloy/config.alloy" = {
      text = ''
        local.file "macAddress" {
          // Alloy service can read file in this specific location
          filename = "/var/lib/private/alloy/MACAddress"
        }

        loki.write "local" {
          endpoint {
            url = "http://localhost:3100/loki/api/v1/push"
          }
        }

        loki.source.api "listener" {
          http {
            listen_address = "${listenerAddress}"
            listen_port = ${toString listenerPort}
          }
          forward_to = [
            loki.write.local.receiver,
          ]
          labels = { systemdJournalLogs = local.file.macAddress.content }
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;
    systemd.services.alloy.serviceConfig.after = ["hw-mac.service"];
  };
}
