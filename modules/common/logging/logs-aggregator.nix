# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  endpointUrl = config.ghaf.logging.server.endpoint;
  listenerAddress = config.ghaf.logging.listener.address;
  listenerPort = toString config.ghaf.logging.listener.port;
  macAddressPath = config.ghaf.logging.identifierFilePath;
in
{
  options.ghaf.logging.server.endpoint = lib.mkOption {
    description = ''
      Assign endpoint url value to the alloy.service running in
      admin-vm. This endpoint URL will include protocol, upstream
      address along with port value.
    '';
    type = lib.types.str;
  };

  config = lib.mkIf config.ghaf.logging.client.enable {
    environment.etc."loki/pass" = {
      text = "ghaf";
    };
    environment.etc."alloy/logs-aggregator.alloy" = {
      text = ''
        local.file "macAddress" {
          // Alloy service can read file in this specific location
          filename = "${macAddressPath}"
        }
        discovery.relabel "adminJournal" {
          targets = []
          rule {
            source_labels = ["__journal__hostname"]
            target_label  = "nodename"
          }
        }

        loki.process "system" {
          forward_to = [loki.write.remote.receiver]
          stage.drop {
            expression = "(GatewayAuthenticator::login|Gateway login succeeded|csd-wrapper|nmcli)"
          }
        }

        loki.source.journal "journal" {
          path          = "/var/log/journal"
          relabel_rules = discovery.relabel.adminJournal.rules
          forward_to    = [loki.write.remote.receiver]
        }

        loki.write "remote" {
          endpoint {
            url = "${endpointUrl}"
            // TODO: To be replaced with stronger authentication method
            basic_auth {
              username = "ghaf"
              password_file = "/etc/loki/pass"
            }
          }
          // Write Ahead Log records incoming data and stores it on the local file
          // system in order to guarantee persistence of acknowledged data.
          wal {
            enabled = true
            max_segment_age = "240h"
            drain_timeout = "4s"
          }
          external_labels = {systemdJournalLogs = local.file.macAddress.content }
        }

        loki.source.api "listener" {
          http {
            listen_address = "${listenerAddress}"
            listen_port = ${listenerPort}
          }

          forward_to = [
            loki.process.system.receiver,
          ]
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;
    systemd.services.alloy.serviceConfig.after = [ "hw-mac.service" ];
    # If there is no internet connection , shutdown/reboot will take around 100sec
    # So, to fix that problem we need to add stop timeout
    # https://github.com/grafana/loki/issues/6533
    systemd.services.alloy.serviceConfig.TimeoutStopSec = 4;
  };
}
