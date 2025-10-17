# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.logging;
in
{
  config = lib.mkIf cfg.server {
    # Password file for basic auth
    environment.etc."loki/pass".text = "ghaf";

    # TLS terminator (stunnel) - accepts mTLS from clients
    services.stunnel = {
      enable = true;
      servers."ghaf-logs" = {
        accept = cfg.listener.port;
        connect = "127.0.0.1:${toString cfg.listener.backendPort}";
        cert = cfg.tls.certFile;
        key = cfg.tls.keyFile;
        verify = if cfg.tls.terminator.verifyClients then 2 else 0;
        sslVersionMin = "TLSv1.2";
      }
      // lib.optionalAttrs (cfg.tls.caFile != null) {
        CAfile = cfg.tls.caFile;
      };
    };

    # Firewall - open listener port
    ghaf.firewall.allowedTCPPorts = [ cfg.listener.port ];

    # Audit rules
    ghaf.security.audit.extraRules = [
      "-w /etc/alloy/config.alloy -p rwxa -k alloy_server_config"
    ]
    ++ lib.optionals cfg.local.enable [
      "-w ${cfg.local.dataDir} -p wa -k loki_data"
    ];

    # Local journal retention
    services.journald.extraConfig = lib.mkIf cfg.journalRetention.enable ''
      MaxRetentionSec=${toString (cfg.journalRetention.maxRetentionDays * 86400)}
      SystemMaxUse=${cfg.journalRetention.maxDiskUsage}
      SystemMaxFileSize=100M
      Storage=persistent
    '';
  };
}
