# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Forward Secure Sealing (FSS) for systemd journal logs
# Provides cryptographic tamper-evidence for audit logs
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    getExe
    optionalString
    optionalAttrs
    ;
  cfg = config.ghaf.logging.fss;
  loggingEnabled = config.ghaf.logging.enable;

  # Script to setup FSS keys on first boot
  setupScript = pkgs.writeShellApplication {
    name = "journal-fss-setup";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
    ];
    text = ''
      set -euo pipefail

      KEY_DIR="${cfg.keyPath}"
      INIT_FILE="$KEY_DIR/initialized"

      # Create key directory if it doesn't exist
      mkdir -p "$KEY_DIR"
      chmod 0700 "$KEY_DIR"

      # Setup FSS keys with specified interval
      echo "Setting up Forward Secure Sealing keys..."
      journalctl --setup-keys --interval="${cfg.sealInterval}" > "$KEY_DIR/setup-output.txt"

      # The sealing key is stored by systemd in /var/lib/systemd/journal/<machine-id>/
      # We extract the verification key from the output for backup
      if grep -q "Verification key" "$KEY_DIR/setup-output.txt"; then
        grep "Verification key" "$KEY_DIR/setup-output.txt" | cut -d: -f2- | tr -d ' ' > "$KEY_DIR/verification-key"
        chmod 0400 "$KEY_DIR/verification-key"
        echo "FSS keys generated successfully"
      else
        echo "Error: Failed to extract verification key"
        exit 1
      fi

      # Create sentinel file to prevent re-initialization
      touch "$INIT_FILE"
      chmod 0644 "$INIT_FILE"

      echo "Forward Secure Sealing initialization complete"
    '';
  };

  # Script to verify journal integrity
  verifyScript = pkgs.writeShellApplication {
    name = "journal-fss-verify";
    runtimeInputs = with pkgs; [
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      echo "Verifying journal integrity with Forward Secure Sealing..."

      if journalctl --verify 2>&1; then
        logger -p auth.info -t journal-fss "AUDIT_LOG_VERIFY_COMPLETED: Journal integrity verification passed"
        echo "Journal integrity verification: PASSED"
        exit 0
      else
        logger -p auth.crit -t journal-fss "AUDIT_LOG_INTEGRITY_FAIL: Journal integrity verification FAILED - potential tampering detected"
        echo "Journal integrity verification: FAILED"
        echo "WARNING: Audit log integrity compromised - alert sent to central logging"
        exit 1
      fi
    '';
  };
in
{
  options.ghaf.logging.fss = {
    enable = mkOption {
      type = types.bool;
      default = loggingEnabled;
      description = ''
        Enable Forward Secure Sealing for systemd journal logs.
        Automatically enabled when ghaf.logging.enable is true.

        FSS provides cryptographic tamper-evidence for audit logs
        using HMAC-based sealing chains. Any tampering will break
        the chain and be detected during verification.
      '';
    };

    keyPath = mkOption {
      type = types.path;
      default = "/persist/common/journal-fss";
      description = ''
        Directory to store FSS keys and metadata.

        Contains:
        - initialized: Sentinel file (prevents re-initialization)
        - verification-key: Public verification key for independent validation
        - setup-output.txt: Full output from key generation

        The sealing key is stored by systemd in /var/lib/systemd/journal/<machine-id>/
        and should never be exported from the host.
      '';
    };

    sealInterval = mkOption {
      type = types.str;
      default = "15min";
      description = ''
        Time interval for sealing journal entries during key generation.

        This interval is set once during 'journalctl --setup-keys' and cannot
        be changed without regenerating keys. Systemd will create a new HMAC
        seal every interval, advancing the forward-secure key chain.

        Shorter intervals provide more granular tamper detection but increase
        storage overhead.

        Format: time span (e.g., "15min", "1h", "30s")
        Recommended: 15min (systemd default)
      '';
    };

    verifyOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run journal verification on system boot.

        Verification will run 2 minutes after systemd-journald starts
        to ensure journal files are ready.
      '';
    };

    verifySchedule = mkOption {
      type = types.str;
      default = "hourly";
      description = ''
        Systemd calendar expression for periodic verification.

        Examples: "hourly", "daily", "weekly", "*:0/30" (every 30 min)
        See systemd.time(7) for full syntax.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Create key directory via tmpfiles
    systemd.tmpfiles.rules = [
      "d ${cfg.keyPath} 0700 root root - -"
    ];

    # One-shot service to generate FSS keys on first boot
    systemd.services.journal-fss-setup = {
      description = "Setup Forward Secure Sealing keys for systemd journal";
      documentation = [ "man:journalctl(1)" ];

      wantedBy = [ "sysinit.target" ];
      before = [ "systemd-journald.service" ];
      after = [ "local-fs.target" ];

      # Only run if not already initialized
      unitConfig.ConditionPathExists = "!${cfg.keyPath}/initialized";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = getExe setupScript;

        # Security hardening
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.keyPath ];
        PrivateNetwork = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "none" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateMounts = true;
      };
    };

    # Service to verify journal integrity
    systemd.services.journal-fss-verify = {
      description = "Verify systemd journal integrity using Forward Secure Sealing";
      documentation = [ "man:journalctl(1)" ];

      after = [ "systemd-journald.service" ];
      wants = [ "systemd-journald.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe verifyScript;

        # Security hardening
        ProtectSystem = "strict";
        PrivateNetwork = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "none" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateMounts = true;

        # Allow read access to journal files
        ReadOnlyPaths = [
          "/var/log/journal"
          "/run/log/journal"
        ];
      };
    };

    # Timer for periodic verification
    systemd.timers.journal-fss-verify = {
      description = "Timer for periodic journal integrity verification";
      documentation = [ "man:journalctl(1)" ];

      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.verifySchedule;
        Persistent = true;
      } // optionalAttrs cfg.verifyOnBoot {
        OnBootSec = "2min";
      };
    };

    # Audit rules to monitor FSS key and journal access
    ghaf.security.audit.extraRules = [
      # Monitor FSS key directory for any write or attribute changes
      "-w ${cfg.keyPath} -p wa -k journal_fss_keys"
      # Monitor sealed journal logs for tampering attempts
      "-w /var/log/journal -p wa -k journal_sealed_logs"
    ];
  };
}
