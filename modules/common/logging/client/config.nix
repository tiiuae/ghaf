# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.logging;
in
{
  config = lib.mkIf cfg.client {
    # Audit logging
    ghaf.security.audit.extraRules = [
      "-w /etc/alloy/config.alloy -p rwxa -k alloy_client_config"
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
