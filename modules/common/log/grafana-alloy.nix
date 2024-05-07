# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  hostName,
  ...
}: let
  logvm-ip-port = "192.168.101.66:3100";
in {
  environment.etc."journal.alloy".text = ''
      discovery.relabel "journal" {
            targets = []

            rule {
                    source_labels = ["__journal__systemd_unit"]
                    target_label  = "unit"
            }
    }

    loki.source.journal "journal" {
            path          = "/var/log/journal"
            relabel_rules = discovery.relabel.journal.rules
            forward_to    = [loki.write.default.receiver]
            labels        = {
                    hostname = "${hostName}",
                    job      = "systemd-journal",
            }
    }

    loki.write "default" {
            endpoint {
                    url = "http://${logvm-ip-port}/loki/api/v1/push"
            }
            external_labels = {}
    }
  '';

  systemd.services.alloy = {
    description = "Alloy service to upload journal logs";
    enable = true;
    after = ["microvm@log-vm.service"];
    serviceConfig = {
      ExecStart = "${pkgs.grafana-alloy}/bin/alloy run /etc/journal.alloy";
      Restart = "on-failure";
      RestartSec = "1";
    };
    wantedBy = ["multi-user.target"];
  };
}
