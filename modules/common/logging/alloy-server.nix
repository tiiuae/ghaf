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
    optionals
    optionalAttrs
    ;
  inherit (lib.strings) hasPrefix;
  cfg = config.ghaf.logging.server;
  alloyHardening = import ../systemd/hardened-configs/alloy.nix;
  dynHostEnabled = config.ghaf.identity.vmHostNameSetter.enable or false;
  givcEnabled = config.ghaf.givc.enable;
  givcHostEnabled = config.ghaf.givc.host.enable;
  needsGivcMount = givcEnabled && !givcHostEnabled;
in
{
  _file = ./alloy-server.nix;

  options.ghaf.logging.server = {
    enable = mkEnableOption "Alloy log forwarder on the logging server";

    endpoint = mkOption {
      description = ''
        Assign remote Loki endpoint URL to the alloy.service running in
        admin-vm. This endpoint URL includes protocol, upstream address,
        and port.
      '';
      type = types.nullOr types.str;
      default = null;
    };

    identifierFilePath = mkOption {
      description = ''
        This configuration option used to specify the identifier file path.
        The identifier file will be text file which have unique identification
        value per machine so that when logs will be uploaded to cloud
        we can identify its origin.
      '';
      type = types.nullOr types.path;
      example = "/etc/common/device-id";
      default = "/etc/common/device-id";
    };

    tls = {
      remoteCAFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional CA bundle used ONLY for server→REMOTE (Grafana Loki) TLS verification.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client certificate (PEM) used for mTLS to remote Loki.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Client private key (PEM) used for mTLS to remote Loki.";
      };

      # Connection options
      serverName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Expected TLS server_name (SNI), e.g., loki.example.com (optional).";
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

  config = mkIf config.ghaf.logging.server.enable {

    assertions = [
      {
        assertion = cfg.endpoint != null;
        message = "Please provide endpoint URL for the Alloy log forwarder, or disable the module.";
      }
      {
        assertion = cfg.identifierFilePath != null;
        message = "Please provide the identifierFilePath for logs aggregator server, or disable the module.";
      }
      {
        assertion = (cfg.tls.certFile != null) && (cfg.tls.keyFile != null);
        message = "Please set ghaf.logging.server.tls.certFile and tls.keyFile.";
      }
      {
        assertion = hasPrefix "https://" (cfg.endpoint or "");
        message = "Endpoint must start with https://";
      }
    ];

    # Local journal retention for admin-vm's own logs
    services = {
      journald.extraConfig = mkIf config.ghaf.logging.journalRetention.enable ''
        MaxRetentionSec=${config.ghaf.logging.journalRetention.maxRetention}
        MaxFileSec=${config.ghaf.logging.journalRetention.MaxFileSec}
        SystemMaxUse=${config.ghaf.logging.journalRetention.maxDiskUsage}
        SystemMaxFileSize=100M
        Storage=persistent
        ${optionalString config.ghaf.logging.fss.enable ''
          Seal=yes
        ''}
      '';

      alloy.enable = true;
    };

    environment.etc = {
      "loki/pass" = {
        text = "ghaf";
      };

      "alloy/logs-aggregator.alloy" = {
        text = ''
          local.file "macAddress" {
            // Alloy service can read file in this specific location
            filename = "${cfg.identifierFilePath}"
          }

          // TLS materials arrive via systemd credentials
          local.file "tls_cert" {
            filename = sys.env("CREDENTIALS_DIRECTORY") + "/loki_cert"
          }
          local.file "tls_key" {
            filename = sys.env("CREDENTIALS_DIRECTORY") + "/loki_key"
          }
          ${optionalString (cfg.tls.remoteCAFile != null) ''
            local.file "remote_ca" {
              filename = sys.env("CREDENTIALS_DIRECTORY") + "/remote_ca"
            }
          ''}
          discovery.relabel "adminJournal" {
            targets = []
            rule {
              source_labels = ["__journal__hostname"]
              target_label  = "host"
            }
            // Populate service_name before Loki falls back to the journal source job.
            // Later rules are more specific and override earlier fallback values.
            rule {
              source_labels = ["__journal__comm"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal_syslog_identifier"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal__systemd_user_unit"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal_user_unit"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal_unit"]
              target_label  = "service_name"
              regex         = "(.+)"
            }
            rule {
              source_labels = ["__journal__transport"]
              target_label  = "transport"
            }
          }

          loki.process "system" {
            forward_to = [loki.write.remote.receiver]
            stage.drop {
              older_than = "15m"
            }
            stage.drop {
              expression = "(GatewayAuthenticator::login|Gateway login succeeded|csd-wrapper|nmcli)"
            }
          }
          loki.source.journal "remote_guests" {
            path = "/var/log/journal/remote"
            relabel_rules = discovery.relabel.adminJournal.rules
            max_age       = "168h"
            forward_to    = [loki.process.system.receiver]
          }

          loki.source.journal "journal" {
            path          = "/var/log/journal"
            relabel_rules = discovery.relabel.adminJournal.rules
            max_age       = "168h"
            forward_to    = [loki.process.system.receiver]
          }

          loki.write "remote" {
            endpoint {
              url = "${cfg.endpoint}"
              // TODO: To be replaced with stronger authentication method
              basic_auth {
                username = "ghaf"
                password_file = "/etc/loki/pass"
              }

              batch_size          = "256KiB"
              max_backoff_period  = "30s"
              max_backoff_retries = 0
              remote_timeout      = "60s"

              tls_config {
                ${optionalString (cfg.tls.remoteCAFile != null) "ca_pem = local.file.remote_ca.content"}
                cert_pem    = local.file.tls_cert.content
                key_pem     = local.file.tls_key.content
                min_version = "${cfg.tls.minVersion}"
                ${optionalString (cfg.tls.serverName != null) ''server_name = "${cfg.tls.serverName}"''}
              }
            }
            // Write Ahead Log records incoming data and stores it on the local file
            // system in order to guarantee persistence of acknowledged data.
            wal {
              enabled = true
              max_segment_age = "168h"
              drain_timeout = "4s"
            }
            external_labels = { machine = local.file.macAddress.content }
          }
        '';
        # The UNIX file mode bits
        mode = "0644";
      };
    };

    systemd.services.alloy = {
      after = [
        "systemd-journald.service"
      ]
      ++ lib.optionals dynHostEnabled [ "set-dynamic-hostname.service" ]
      ++ lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      requires = [ "systemd-journald.service" ];
      wants = lib.optionals givcHostEnabled [ "givc-key-setup.service" ];

      unitConfig = lib.optionalAttrs needsGivcMount {
        RequiresMountsFor = [ "/etc/givc" ];
      };

      serviceConfig = (optionalAttrs config.ghaf.systemd.withHardenedConfigs alloyHardening) // {

        SupplementaryGroups = [
          "systemd-journal"
          "adm"
        ];

        # If there is no internet connection , shutdown/reboot will take around 100sec
        # So, to fix that problem we need to add stop timeout
        # https://github.com/grafana/loki/issues/6533
        TimeoutStopSec = 25;

        # Copy certs/keys (and optional remote CA) into /run/credentials/alloy.service/…
        LoadCredential = [
          "loki_cert:${cfg.tls.certFile}"
          "loki_key:${cfg.tls.keyFile}"
        ]
        ++ optionals (cfg.tls.remoteCAFile != null) [
          "remote_ca:${cfg.tls.remoteCAFile}"
        ];
      };
    };

    ghaf.security.audit.extraRules = [
      "-w /etc/alloy/logs-aggregator.alloy -p rwxa -k alloy_server_config"
    ];
  };
}
