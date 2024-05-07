# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  endpointUrl = config.ghaf.logging.server.endpoint;
  listenerAddress = config.ghaf.logging.listener.address;
  listenerPort = toString config.ghaf.logging.listener.port;
  macAddressPath = config.ghaf.logging.identifierFilePath;
in {
  options.ghaf.logging.server.endpoint = lib.mkOption {
    description = ''
      Assign endpoint url value to the alloy.service running in
      admin-vm. This endpoint URL will include protocol, upstream
      address along with port value.
    '';
    type = lib.types.str;
  };

  config = lib.mkIf config.ghaf.logging.client.enable {
    environment.etc."alloy/logs-aggregator.alloy" = {
      text = ''
        local.file "macAddress" {
          // Alloy service can read file in this specific location
          filename = "${macAddressPath}"
        }

        loki.write "remote" {
          endpoint {
            url = "${endpointUrl}"
          }
          external_labels = {systemdJournalLogs = local.file.macAddress.content }
        }

        loki.source.api "listener" {
          http {
            listen_address = "${listenerAddress}"
            listen_port = ${listenerPort}
          }

          forward_to = [
            loki.write.remote.receiver,
          ]
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;
    systemd.services.alloy.serviceConfig.after = ["hw-mac.service"];
    # If there is no internet connection , shutdown/reboot will take around 100sec
    # So, to fix that problem we need to add stop timeout
    systemd.services.alloy.serviceConfig.TimeoutStopSec = 2;
  };
}
