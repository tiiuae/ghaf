# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    optionalString
    ;
  cfg = config.ghaf.logging.client;
  inherit (config.ghaf.logging) listener;
  dynHostEnabled = config.ghaf.identity.vmHostNameSetter.enable or false;
in
{
  options.ghaf.logging.client = {
    enable = mkEnableOption "Alloy client service";
    endpoint = mkOption {
      description = ''
        Assign endpoint url value to the alloy.service running in
        different log producers. This endpoint URL will include
        protocol, upstream, address along with port value.
      '';
      type = types.str;
      default = "https://${listener.address}:${toString listener.port}/loki/api/v1/push";
    };

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "CA bundle used to verify the admin-vm TLS terminator certificate.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client certificate (PEM) used for mTLS to the admin-vm.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Client private key (PEM) used for mTLS to the admin-vm.";
      };
      minVersion = mkOption {
        type = types.nullOr (
          types.enum [
            "TLS12"
            "TLS13"
          ]
        );
        default = "TLS12";
        description = "Minimum TLS version for the outbound connection.";
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = listener.address != "";
        message = "Please provide a listener address, or disable the module.";
      }
      {
        assertion = (cfg.tls.certFile != null) && (cfg.tls.keyFile != null);
        message = "Please set ghaf.logging.client.tls.certFile and tls.keyFile for mTLS.";
      }
    ];

    # Local journal retention
    services.journald.extraConfig = mkIf config.ghaf.logging.journalRetention.enable ''
      MaxRetentionSec=${config.ghaf.logging.journalRetention.maxRetention}
      MaxFileSec=${config.ghaf.logging.journalRetention.MaxFileSec}
      SystemMaxUse=${config.ghaf.logging.journalRetention.maxDiskUsage}
      SystemMaxFileSize=100M
      Storage=persistent
    '';

    environment.etc."alloy/client.alloy" = {
      text = ''
        discovery.relabel "journal" {
          targets = []
          rule {
            source_labels = ["__journal__hostname"]
            target_label  = "host"
          }
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "service_name"
          }
          rule {
            source_labels = ["__journal__transport"]
            target_label  = "transport"
          }
        }

        loki.source.journal "journal" {
          path          = "/var/log/journal"
          relabel_rules = discovery.relabel.journal.rules
          max_age       = "168h"
          forward_to    = [loki.write.adminvm.receiver]
        }

        loki.write "adminvm" {
          endpoint {
            url = "${cfg.endpoint}"
            tls_config {
              ${optionalString (
                cfg.tls.caFile != null
              ) ''ca_file = sys.env("CREDENTIALS_DIRECTORY") + "/client_ca"''}
              cert_file   = sys.env("CREDENTIALS_DIRECTORY") + "/client_cert"
              key_file    = sys.env("CREDENTIALS_DIRECTORY") + "/client_key"
              min_version = "${cfg.tls.minVersion}"
            }
          }
        }
      '';
      # The UNIX file mode bits
      mode = "0644";
    };

    services.alloy.enable = true;

    systemd.services.alloy.serviceConfig = {
      after = [
        "systemd-journald.service"
      ]
      ++ lib.optionals dynHostEnabled [ "set-dynamic-hostname.service" ];
      requires = [ "systemd-journald.service" ];

      SupplementaryGroups = [
        "systemd-journal"
        "adm"
      ];

      # Once alloy.service in admin-vm stopped this service will
      # still keep on retrying to send logs batch, so we need to
      # stop it forcefully.
      TimeoutStopSec = 4;

      # Copy certs/keys (and optional CA) into /run/credentials/alloy.service/…
      LoadCredential = [
        "client_cert:${cfg.tls.certFile}"
        "client_key:${cfg.tls.keyFile}"
      ]
      ++ lib.optionals (cfg.tls.caFile != null) [
        "client_ca:${cfg.tls.caFile}"
      ];
    };

    ghaf.security.audit.extraRules = [
      "-w /etc/alloy/client.alloy -p rwxa -k alloy_client_config"
    ];
  };
}
