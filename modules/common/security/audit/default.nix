# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.security.audit;
  inherit (lib)
    mkOption
    mkIf
    types
    optionals
    literalExpression
    mkEnableOption
    ;

  importAuditRules =
    ruleSet:
    import (./. + "/rules/${ruleSet}.nix") {
      inherit config pkgs lib;
    };

in
{
  options.ghaf.security.audit = {
    enable = mkEnableOption "Enable audit support";
    debug = mkOption {
      type = types.bool;
      default = true; # for now
      description = "Enable audit debug mode";
    };
    commonRules = mkOption {
      type = types.listOf types.str;
      default = importAuditRules "common";
      description = "Common audit rules for host and guests";
    };
    enableVerboseCommon = mkOption {
      type = types.bool;
      default = false;
      description = "Include verbose Common audit rules";
    };
    enableStig = mkOption {
      type = types.bool;
      default = false;
      description = "Enable STIG rules";
    };
    enableOspp = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OSPP rules";
    };
    enableVerboseOspp = mkOption {
      type = types.bool;
      default = false;
      description = "Include verbose OSPP rules";
    };
    enableVerboseRebuild = mkOption {
      type = types.bool;
      default = false;
      description = "Include verbose nixos-rebuild rule";
    };
    host = {
      enable = mkOption {
        type = types.bool;
        default = config.ghaf.type == "host";
        defaultText = literalExpression ''
          config.ghaf.type == "host";
        '';
        description = "Enable host audit rules";
      };
      rules = mkOption {
        type = types.listOf types.str;
        default = importAuditRules "host";
        description = "Basic host audit rules";
      };
    };
    guest = {
      enable = mkOption {
        type = types.bool;
        default = config.ghaf.type != "host";
        defaultText = literalExpression ''
          config.ghaf.type != "host";
        '';
        description = "Enable guest audit rules";
      };
      rules = mkOption {
        type = types.listOf types.str;
        default = importAuditRules "guest";
        description = "Basic guest audit rules";
      };
    };
    extraRules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of additional audit rules";
    };
  };

  config = mkIf cfg.enable {

    ghaf.systemd.withAudit = true;
    security.auditd.enable = true;
    ghaf.security.audit.enableOspp = mkIf cfg.enableVerboseOspp true;

    security.audit = {
      enable = true;
      failureMode = if cfg.debug then "printk" else "panic";
      backlogLimit = 8192;
      rules =
        cfg.commonRules
        ++ cfg.extraRules
        ++ optionals cfg.host.enable cfg.host.rules
        ++ optionals cfg.guest.enable cfg.guest.rules;
    };

    boot.kernelParams = [
      "audit_backlog_limit=${toString config.security.audit.backlogLimit}"
    ];

    environment.etc."audit/auditd.conf".text = ''
      log_file = /var/log/audit/audit.log
      log_format = RAW
      flush = INCREMENTAL_ASYNC
      freq = 512
      num_logs = 5
      name_format = HOSTNAME
      max_log_file = 10
      max_log_file_action = ROTATE
      space_left = 10%
      space_left_action = SYSLOG
      admin_space_left = 5%
      admin_space_left_action = SINGLE
      disk_full_action = ROTATE
      disk_error_action = SUSPEND
    '';
  };
}
