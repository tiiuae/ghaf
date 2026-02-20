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
  _file = ./default.nix;

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
    enableVerboseCommon = mkEnableOption "verbose Common audit rules";
    enableStig = mkEnableOption "STIG rules";
    enableOspp = mkEnableOption "OSPP rules";
    enableVerboseOspp = mkEnableOption "verbose OSPP rules";
    enableVerboseRebuild = mkEnableOption "verbose nixos-rebuild rule";
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

    systemd = {
      services.audit-rules-nixos = {
        serviceConfig.ExecStart =
          let
            auditRulesFile = pkgs.writeText "ghaf-audit.rules" (
              lib.concatStringsSep "\n" ([ "-D" ] ++ config.security.audit.rules)
            );
          in
          lib.mkForce "${pkgs.audit}/bin/auditctl -R ${auditRulesFile}";

        # Let systemd use default ordering for audit-rules instead of early-boot
        unitConfig.DefaultDependencies = lib.mkForce true;
        unitConfig.RequiresMountsFor = [
          "/etc/givc"
          "/etc/common/journal-fss"
          "/var/log/journal"
        ];
        before = lib.mkForce [ ];
      };

      # Systemd oneshot service to immediate rotation, obeying num_logs.
      services.auditd-rotate = {
        description = "Time-based rotation of audit logs";
        after = [ "auditd.service" ];
        wants = [ "auditd.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.audit}/bin/auditctl --signal rotate";
        };
      };

      # Systemd timer: when to rotate.
      # Default = daily. It is possible to change OnCalendar for testing (e.g. "minutely")
      timers.auditd-rotate = {
        description = "Periodic audit log rotation (time-based)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };

    environment.etc."audit/auditd.conf".text = ''
      log_file = /var/log/audit/audit.log
      log_format = RAW
      flush = INCREMENTAL_ASYNC
      freq = 512
      num_logs = 30
      name_format = HOSTNAME
      max_log_file = 10
      max_log_file_action = IGNORE
      space_left = 10%
      space_left_action = SYSLOG
      admin_space_left = 5%
      admin_space_left_action = SINGLE
      disk_full_action = ROTATE
      disk_error_action = SUSPEND
    '';
  };
}
