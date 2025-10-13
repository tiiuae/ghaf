# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.logging;

  text = with lib; ''
    // ============================================
    // CLIENT CONFIGURATION
    // Sends logs to admin-vm for aggregation
    // ============================================

    // TLS credentials from systemd
    local.file "tls_cert" {
      filename = sys.env("CREDENTIALS_DIRECTORY") + "/loki_cert"
    }
    local.file "tls_key" {
      filename = sys.env("CREDENTIALS_DIRECTORY") + "/loki_key"
    }
    ${optionalString (cfg.tls.caFile != null) ''
      local.file "tls_ca" {
        filename = sys.env("CREDENTIALS_DIRECTORY") + "/loki_ca"
      }
    ''}

    // Collect local journal logs
    loki.source.journal "journal" {
      path       = "/var/log/journal"
      forward_to = [loki.write.server.receiver]
    }

    // Forward to admin-vm
    loki.write "server" {
      endpoint {
        url = "https://${cfg.listener.address}:${toString cfg.listener.port}/loki/api/v1/push"

        tls_config {
          ${optionalString (cfg.tls.caFile != null) ''ca_pem = local.file.tls_ca.content,''}
          cert_pem    = local.file.tls_cert.content,
          key_pem     = local.file.tls_key.content,
          min_version = "${cfg.tls.minVersion}",
        }
      }

      // Write-Ahead Log for reliability
      wal {
        enabled         = true
        max_segment_age = "240h"
        drain_timeout   = "4s"
      }

      // Only add hostname label
      external_labels = {
        hostname = env("HOSTNAME")
      }
    }
  '';

  # Validation check at evaluation time
  configFile = pkgs.writeText "alloy-client-config.alloy" text;

  configCheck =
    pkgs.runCommand "alloy-client-config-check"
      {
        nativeBuildInputs = [ pkgs.grafana-alloy ];
      }
      ''
        alloy fmt ${configFile}
        touch $out
      '';
in
{
  config = lib.mkIf cfg.client {
    # Ensure config is validated at build time
    system.checks = [ configCheck ];

    environment.etc."alloy/config.alloy" = {
      inherit text;
      mode = "0644";
    };

    # Enable Alloy service
    services.alloy = {
      enable = true;
      configPath = "/etc/alloy/config.alloy";
    };

    # Systemd service configuration
    systemd.services.alloy.serviceConfig = {
      # Load TLS credentials from secure location
      LoadCredential = [
        "loki_cert:${cfg.tls.certFile}"
        "loki_key:${cfg.tls.keyFile}"
      ]
      ++ lib.optionals (cfg.tls.caFile != null) [
        "loki_ca:${cfg.tls.caFile}"
      ];

      # Allow reading journal
      SupplementaryGroups = [ "systemd-journal" ];

      # Quick shutdown
      TimeoutStopSec = 4;
    };
  };
}
