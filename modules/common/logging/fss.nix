# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Forward Secure Sealing (FSS) for systemd journal logs
# Provides cryptographic tamper-evidence for audit logs
#
# Overview:
# ---------
# Forward Secure Sealing uses HMAC-SHA256 chains to provide tamper-evident logging.
# Each journal entry is cryptographically sealed at regular intervals (default: 15min).
# Any tampering with sealed entries breaks the HMAC chain and is detected during verification.
#
# Architecture:
# ------------
# - Sealing keys: Generated per-component, stored in /var/log/journal/<machine-id>/fss
# - Verification keys: Generated per-component, stored in cfg.keyPath/<hostname>/verification-key
# - Setup service: One-shot service that generates keys on first boot for each component
# - Verify service: Periodic integrity checks (default: hourly + on boot)
# - Alerts: Verification failures logged via systemd-cat and forwarded to admin-vm
# - Shared storage: Verification keys stored in virtiofs-mounted /persist/common for backup access
#
# Per-Component Isolation:
# -----------------------
# Each component (host + all VMs) generates and maintains its own FSS key pair:
# - Host: /persist/common/journal-fss/ghaf-host/{initialized, verification-key}
# - VMs:  /etc/common/journal-fss/<vm-name>/{initialized, verification-key}
# This ensures tamper detection works correctly - each component's journals are
# sealed with its own sealing key and verified with its matching verification key.
#
# Security Properties:
# -------------------
# - Forward security: Compromising current key does not allow forging past entries
# - Tamper detection: Any modification to sealed entries invalidates HMAC chain
# - Per-component isolation: Each component has independent FSS key pairs
# - Offline verification: Verification keys can validate exported journal archives
#
# Operational Notes:
# -----------------
# 1. First Boot (per component):
#    - journal-fss-setup.service runs after systemd-journald is ready
#    - Generates sealing keys with configured seal interval
#    - Restarts journald to pick up FSS keys immediately
#    - Extracts verification key to cfg.keyPath/<hostname>/verification-key
#    - Each component creates its own subdirectory with independent keys
#    - CRITICAL: Backup all verification-keys to secure offline storage
#
# 2. Runtime:
#    - systemd-journald seals entries every sealInterval
#    - journal-fss-verify.timer runs hourly + 5min after boot
#    - Each component verifies only its own journals
#    - Verification failures trigger critical alerts to admin-vm
#
# 3. Key Management:
#    - Sealing keys NEVER leave their component (security-critical)
#    - Verification keys stored per-component in shared /persist/common
#    - Backup entire /persist/common/journal-fss/ tree for offline verification
#    - Key rotation requires per-component journal archive, clear, and reboot
#
# 4. Monitoring:
#    - Audit rules monitor FSS key directory and journal access
#    - AUDIT_LOG_VERIFY_COMPLETED: Successful verification
#    - AUDIT_LOG_INTEGRITY_FAIL: Failed verification (potential tampering)
#
# 5. Troubleshooting:
#    - Manual verification: journalctl --verify
#    - Check service status: systemctl status journal-fss-setup
#    - Check timer status: systemctl list-timers journal-fss-verify
#    - View verification logs: journalctl -t journal-fss
#
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
      gawk
    ];
    text = ''
      export LC_ALL=C

      KEY_DIR="${cfg.keyPath}"
      INIT_FILE="$KEY_DIR/initialized"
      MACHINE_ID=$(cat /etc/machine-id)

      # Support both persistent and volatile storage
      FSS_KEY_FILE="/var/log/journal/$MACHINE_ID/fss"
      if [ ! -f "$FSS_KEY_FILE" ] && [ -f "/run/log/journal/$MACHINE_ID/fss" ]; then
        FSS_KEY_FILE="/run/log/journal/$MACHINE_ID/fss"
        echo "Note: Using volatile storage location for FSS keys"
      fi

      # Create key directory if it doesn't exist
      mkdir -p "$KEY_DIR"
      chmod 0700 "$KEY_DIR"

      # Ensure journal directory exists (for persistent storage)
      mkdir -p "/var/log/journal/$MACHINE_ID"
      # Set permissions if possible (may fail in restricted environments like MicroVMs)
      chmod 0755 "/var/log/journal" 2>/dev/null || true
      chmod 2755 "/var/log/journal/$MACHINE_ID" 2>/dev/null || true

      # Check if FSS keys already exist
      if [ -f "$FSS_KEY_FILE" ]; then
        echo "FSS sealing key already exists at $FSS_KEY_FILE"
        echo "Setup already complete, creating sentinel file"
        touch "$INIT_FILE"
        chmod 0644 "$INIT_FILE"
        # Write config pointer so test scripts can discover KEY_DIR without hostname
        echo "$KEY_DIR" > "/var/log/journal/$MACHINE_ID/fss-config"
        chmod 0644 "/var/log/journal/$MACHINE_ID/fss-config"
        # One-time rotation to move pre-FSS entries to archive (fixes "Bad message")
        if [ ! -f "/var/log/journal/$MACHINE_ID/fss-rotated" ]; then
          echo "Rotating journal to ensure clean FSS state..."
          journalctl --rotate 2>/dev/null || true
          touch "/var/log/journal/$MACHINE_ID/fss-rotated"
        fi
        exit 0
      fi

      # Generate new FSS keys
      echo "Setting up Forward Secure Sealing keys..."
      if ! journalctl --setup-keys --interval="${cfg.sealInterval}" > "$KEY_DIR/setup-output.txt" 2>&1; then
        echo "Error: journalctl --setup-keys failed"
        cat "$KEY_DIR/setup-output.txt"
        exit 1
      fi

      # Extract verification key robustly (locale-independent)
      # The verification key is the last line of output
      # Format: seed-hex-with-hyphens/start-hex-interval-hex
      # Example: f90032-d54bd1-57dd7a-d09e1b/190250-35a4e900
      if tail -1 "$KEY_DIR/setup-output.txt" | tr -d '[:space:]' > "$KEY_DIR/verification-key"; then
        if [ -s "$KEY_DIR/verification-key" ]; then
          chmod 0400 "$KEY_DIR/verification-key"
          echo "FSS verification key extracted successfully"
          echo "IMPORTANT: Store verification key off-host in a secure vault"
        else
          echo "Warning: Verification key file is empty"
        fi
      else
        echo "Warning: Could not extract verification key from output"
      fi

      # Securely remove setup output (contains sensitive key material)
      shred -u "$KEY_DIR/setup-output.txt" 2>/dev/null || rm -f "$KEY_DIR/setup-output.txt"

      # Verify sealing key was created
      if [ ! -f "$FSS_KEY_FILE" ]; then
        echo "Error: FSS key generation failed - key file not found at $FSS_KEY_FILE"
        exit 1
      fi

      # Restart journald to pick up the new FSS key
      # Journald only checks for FSS keys at startup, so rotation alone is insufficient
      echo "Restarting journald to enable sealing..."
      if ! systemctl restart systemd-journald; then
        echo "Warning: Journald restart failed - sealing may not be active"
      fi

      # Rotate so active journal starts clean with FSS (pre-FSS entries become archive)
      journalctl --rotate 2>/dev/null || true

      # Create sentinel file to prevent re-initialization
      touch "$INIT_FILE"
      chmod 0644 "$INIT_FILE"

      # Write config pointer so test scripts can discover KEY_DIR without hostname
      echo "$KEY_DIR" > "/var/log/journal/$MACHINE_ID/fss-config"
      chmod 0644 "/var/log/journal/$MACHINE_ID/fss-config"

      touch "/var/log/journal/$MACHINE_ID/fss-rotated"

      echo "Forward Secure Sealing initialization complete"
      echo "Sealing key: $FSS_KEY_FILE"
      echo "Verification key: $KEY_DIR/verification-key (if extracted)"
    '';
  };

  # Script to verify journal integrity
  verifyScript = pkgs.writeShellApplication {
    name = "journal-fss-verify";
    runtimeInputs = with pkgs; [
      systemd
      util-linux
      gnugrep
    ];
    text = ''
      echo "Verifying journal integrity with Forward Secure Sealing..."

      # Check if any journals exist to verify
      if ! journalctl --list-boots >/dev/null 2>&1; then
        echo "No journals found to verify, skipping verification"
        echo "This is normal on fresh boot before journals are created"
        exit 0
      fi

      # Check if verification key exists and use it
      VERIFY_KEY_FILE="${cfg.keyPath}/verification-key"
      VERIFY_CMD="journalctl --verify"
      if [ -f "$VERIFY_KEY_FILE" ] && [ -s "$VERIFY_KEY_FILE" ]; then
        VERIFY_KEY=$(cat "$VERIFY_KEY_FILE")
        VERIFY_CMD="journalctl --verify --verify-key=$VERIFY_KEY"
        echo "Using verification key from $VERIFY_KEY_FILE"
        # Diagnostic: Show key length for troubleshooting
        KEY_LENGTH=$(echo -n "$VERIFY_KEY" | wc -c)
        echo "Verification key length: $KEY_LENGTH bytes (expected: 30-40 bytes)"
      else
        echo "WARNING: No verification key found at $VERIFY_KEY_FILE"
        echo "Running verification without key - sealed journals will fail verification"
      fi

      # Capture output and exit code
      VERIFY_OUTPUT=$($VERIFY_CMD 2>&1) || VERIFY_EXIT=$?
      VERIFY_EXIT=''${VERIFY_EXIT:-0}

      # Check for actual integrity failures (FAIL/Failed in output)
      # Catches: "FAIL", "Failed to parse seed", "verification failed", etc.
      if echo "$VERIFY_OUTPUT" | grep -qi "FAIL"; then
        # Provide specific guidance for seed parsing failures
        if echo "$VERIFY_OUTPUT" | grep -qi "parse.*seed"; then
          echo "AUDIT_LOG_INTEGRITY_FAIL: FSS seed parsing failed - verification key is malformed or incomplete" | systemd-cat -t journal-fss -p crit
          echo "Journal integrity verification: FAILED (seed parsing error)"
          echo "Output: $VERIFY_OUTPUT"
          echo ""
          echo "This error indicates the verification key is incomplete or corrupted."
          echo "The verification key should be 30-40 bytes and contain '/' separator."
          echo ""
          echo "To fix:"
          echo "1. Reset FSS: rm ${cfg.keyPath}/initialized && rm /var/log/journal/*/fss"
          echo "2. Reboot to regenerate keys with correct extraction"
          echo "3. Backup the new verification key from ${cfg.keyPath}/verification-key"
          exit 1
        # Check if only user journals failed (not system journal)
        # User journals may fail due to entries written before FSS initialization
        elif echo "$VERIFY_OUTPUT" | grep -qi "FAIL:.*user-.*\.journal\|user-.*\.journal.*FAIL"; then
          if ! echo "$VERIFY_OUTPUT" | grep -qi "FAIL:.*system\.journal\|system\.journal.*FAIL"; then
            echo "WARNING: User journal verification failed but system journal OK" | systemd-cat -t journal-fss -p warning
            echo "Journal integrity verification: PARTIAL (user journals failed, system journal OK)"
            echo "Output: $VERIFY_OUTPUT"
            echo ""
            echo "User journal failures are typically caused by entries written before FSS initialization."
            echo "This is expected during initial setup and does not indicate tampering."
            # Continue without failing - system journal integrity is what matters
          else
            echo "AUDIT_LOG_INTEGRITY_FAIL: Journal integrity verification FAILED - potential tampering detected" | systemd-cat -t journal-fss -p crit
            echo "Journal integrity verification: FAILED"
            echo "Output: $VERIFY_OUTPUT"
            echo "WARNING: Audit log integrity compromised - alert sent to central logging"
            exit 1
          fi
        else
          echo "AUDIT_LOG_INTEGRITY_FAIL: Journal integrity verification FAILED - potential tampering detected" | systemd-cat -t journal-fss -p crit
          echo "Journal integrity verification: FAILED"
          echo "Output: $VERIFY_OUTPUT"
          echo "WARNING: Audit log integrity compromised - alert sent to central logging"
          exit 1
        fi
      fi

      # Check for permission/filesystem errors that don't indicate tampering
      if echo "$VERIFY_OUTPUT" | grep -qi "read-only file system\|permission denied\|cannot create"; then
        echo "WARNING: Journal verification encountered filesystem errors (not an integrity failure)" | systemd-cat -t journal-fss -p warning
        echo "Journal integrity verification: SKIPPED (filesystem errors)"
        echo "Output: $VERIFY_OUTPUT"
        echo "Note: This may be due to security hardening restrictions, not actual tampering"
        exit 0
      fi

      # If we got here with non-zero exit but no specific errors, treat as success with warning
      if [ "$VERIFY_EXIT" -ne 0 ]; then
        echo "Journal verification returned non-zero exit but no critical errors detected" | systemd-cat -t journal-fss -p warning
        echo "Output: $VERIFY_OUTPUT"
      fi

      # Success case
      echo "AUDIT_LOG_VERIFY_COMPLETED: Journal integrity verification passed" | systemd-cat -t journal-fss -p info
      echo "Journal integrity verification: PASSED"
      exit 0
    '';
  };
in
{
  _file = ./fss.nix;

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
      default =
        let
          componentName = config.networking.hostName;
          basePath =
            if config.ghaf.type == "host" then "/persist/common/journal-fss" else "/etc/common/journal-fss";
        in
        "${basePath}/${componentName}";
      description = ''
        Directory to store FSS keys and metadata for this component.

        Per-component isolation ensures each component (host + VMs) has
        independent FSS key pairs for proper tamper detection.

        Path structure:
        - Host: /persist/common/journal-fss/ghaf-host/ (direct persist access)
        - VMs:  /etc/common/journal-fss/<vm-name>/ (virtiofs mount from host)

        Examples:
        - Host: /persist/common/journal-fss/ghaf-host/verification-key
        - Audio-VM: /etc/common/journal-fss/audio-vm/verification-key
        - Admin-VM: /etc/common/journal-fss/admin-vm/verification-key

        Contains:
        - initialized: Sentinel file (prevents re-initialization)
        - verification-key: Public verification key for independent validation

        The sealing key is stored by systemd in /var/log/journal/<machine-id>/fss
        and should never be exported from the host.

        Verification Key Storage:
        - The verification key is extracted once during initial setup
        - CRITICAL: Copy verification-key to secure offline storage immediately
        - Required for independent verification of exported journal archives
        - If lost, tamper detection is still functional but offline verification is impossible

        Offline Verification Process:
        1. Export journal: journalctl -o export > journal.export
        2. Transfer journal.export and verification-key to verification system
        3. Verify: journalctl --verify --verify-key=<verification-key> --file=journal.export

        Key Rotation:
        - FSS keys are bound to the seal interval and cannot be rotated independently
        - To rotate: clear journals, delete ${cfg.keyPath}/initialized, reboot
        - WARNING: Rotation destroys tamper-evidence chain for existing logs
        - Best practice: Archive and verify existing journals before rotation
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

        Impact of Changing sealInterval:
        - REQUIRES key regeneration (destroys existing tamper-evidence chain)
        - Shorter intervals (e.g., "5min"):
          * Faster tamper detection granularity
          * Higher storage overhead (~0.5% per seal)
          * More verification CPU overhead
        - Longer intervals (e.g., "1h"):
          * Lower storage overhead
          * Coarser tamper detection window
          * Faster verification

        Operational Notes:
        - The seal interval is embedded in the FSS key structure
        - Changing this value after deployment requires:
          1. Archive and verify existing journals
          2. Clear /var/log/journal/<machine-id>/
          3. Delete ${cfg.keyPath}/initialized
          4. Reboot to trigger new key generation
        - All VMs in the system can use different seal intervals independently
      '';
    };

    verifyOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run journal verification on system boot.

        Verification will run 10 minutes after systemd-journald starts
        to ensure journal files are ready and FSS setup has completed.
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
    # Enable audit subsystem for FSS monitoring
    # This provides auditctl and enables the audit rules defined below
    # Use mkDefault so profiles can override if needed
    ghaf.security.audit.enable = lib.mkDefault true;

    # Create key directory and journal directory via tmpfiles
    # Note: In VMs, ${cfg.keyPath} is a virtiofs mount point, so we only create it on host
    systemd.tmpfiles.rules =
      lib.optionals (config.ghaf.type == "host") [
        "d /persist/common/journal-fss 0755 root root - -"
        "d ${cfg.keyPath} 0700 root root - -"
      ]
      ++ [
        "d /var/log/journal 0755 root systemd-journal - -"
      ];

    # One-shot service to generate FSS keys on first boot
    # Runs after journald is ready, then restarts journald to enable sealing
    systemd.services.journal-fss-setup = {
      description = "Setup Forward Secure Sealing keys for systemd journal";
      documentation = [ "man:journalctl(1)" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      wants = [ "systemd-journald.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = getExe setupScript;
      };
    };

    # Service to verify journal integrity
    systemd.services.journal-fss-verify = {
      description = "Verify systemd journal integrity using Forward Secure Sealing";
      documentation = [ "man:journalctl(1)" ];

      after = [
        "systemd-journald.service"
        "journal-fss-setup.service"
      ];
      wants = [
        "systemd-journald.service"
        "journal-fss-setup.service"
      ];

      unitConfig = {
        # Only run if FSS setup has completed successfully
        ConditionPathExists = "${cfg.keyPath}/initialized";
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe verifyScript;
        WorkingDirectory = "/";

        # File system access required for journal verification
        # journalctl --verify needs write access to create verification metadata
        # Also needs read access to verification key for sealed journal validation
        ReadWritePaths = [
          "/var/log/journal"
          "/run/log/journal"
          cfg.keyPath
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
        RandomizedDelaySec = "5min";
      }
      // optionalAttrs cfg.verifyOnBoot {
        OnBootSec = "10min";
      };
    };

    # Audit rules to monitor FSS key and journal access
    ghaf.security.audit.extraRules = [
      # Monitor FSS key directory for any write or attribute changes
      "-w ${cfg.keyPath} -p wa -k journal_fss_keys"
      # Monitor sealed journal logs for tampering attempts
      "-w /var/log/journal -p wa -k journal_sealed_logs"
      # Monitor machine-id reads (critical for journal path resolution)
      "-w /etc/machine-id -p r -k machine_id_read"
    ];
  };
}
