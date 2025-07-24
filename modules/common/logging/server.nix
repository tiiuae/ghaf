# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.logging.server;
in
{
  options.ghaf.logging.server = {
    enable = lib.mkEnableOption "Enable logs aggregator server";
    endpoint = lib.mkOption {
      description = ''
        Assign endpoint url value to the alloy.service running in
        admin-vm. This endpoint URL will include protocol, upstream
        address along with port value.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    identifierFilePath = lib.mkOption {
      description = ''
        This configuration option used to specify the identifier file path.
        The identifier file will be text file which have unique identification
        value per machine so that when logs will be uploaded to cloud
        we can identify its origin.
      '';
      type = lib.types.nullOr lib.types.path;
      example = "/etc/common/device-id";
      default = "/etc/common/device-id";
    };
  };

  config = lib.mkIf config.ghaf.logging.server.enable {

    assertions = [
      {
        assertion = cfg.endpoint != null;
        message = "Please provide endpoint URL for logs aggregator server, or disable the module.";
      }
      {
        assertion = cfg.identifierFilePath != null;
        message = "Please provide the identifierFilePath for logs aggregator server, or disable the module.";
      }
    ];

    environment.etc."loki/pass" = {
      text = "ghaf";
    };

    environment.etc."alloy/logs-aggregator.alloy" = {
      text = ''
        local.file "macAddress" {
          // Alloy service can read file in this specific location
          filename = "${cfg.identifierFilePath}"
        }

        discovery.relabel "adminJournal" {
          targets = []
          rule {
            source_labels = ["__journal__hostname"]
            target_label  = "host"
          }
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "service_name"
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
            url = "${cfg.endpoint}"
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
          external_labels = { machine = local.file.macAddress.content }
        }

        loki.source.api "listener" {
          http {
            listen_address = "${config.ghaf.logging.listener.address}"
            listen_port = ${toString config.ghaf.logging.listener.port}
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
    # If there is no internet connection , shutdown/reboot will take around 100sec
    # So, to fix that problem we need to add stop timeout
    # https://github.com/grafana/loki/issues/6533
    systemd.services.alloy.serviceConfig.TimeoutStopSec = 4;

    ghaf.firewall = {
      allowedTCPPorts = [ config.ghaf.logging.listener.port ];
      allowedUDPPorts = [ ];
    };

    ghaf.security.audit.extraRules = [
      "-w /etc/alloy/logs-aggregator.alloy -p rwxa -k alloy_client_config"
    ];
  };
}
