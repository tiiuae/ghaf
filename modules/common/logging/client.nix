# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.logging.client;
  endpointUrl = config.ghaf.logging.client.endpoint;
in
{
  options.ghaf.logging.client.endpoint = lib.mkOption {
    description = ''
      Assign endpoint url value to the alloy.service running in
      different log producers. This endpoint URL will include
      protocol, upstream, address along with port value.
    '';
    type = lib.types.str;
  };

  config = lib.mkIf cfg.enable {
    environment.etc."alloy/client.alloy" = {
      text = ''
        discovery.relabel "journal" {
          targets = []
          rule {
            source_labels = ["__journal__hostname"]
            target_label  = "nodename"
          }
        }

        loki.source.journal "journal" {
          path          = "/var/log/journal"
          relabel_rules = discovery.relabel.journal.rules
          forward_to    = [loki.write.adminvm.receiver]
        }

        loki.write "adminvm" {
          endpoint {
            url = "${endpointUrl}"
          }
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;
    # Once alloy.service in admin-vm stopped this service will
    # still keep on retrying to send logs batch, so we need to
    # stop it forcefully.
    systemd.services.alloy.serviceConfig.TimeoutStopSec = 4;
  };
}
