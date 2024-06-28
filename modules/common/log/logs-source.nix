# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  hostName,
  ...
}: let
  admin-ip-port = "admin-vm-debug:${toString config.ghaf.logging.listener.port}";
  cfg = config.ghaf.logging.client;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.grafana-alloy];

    environment.etc."alloy/config.alloy" = {
      text = ''
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
            url = "http://${admin-ip-port}/loki/api/v1/push"
          }
          external_labels = {}
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;
  };
}
