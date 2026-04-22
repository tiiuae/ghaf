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
#    - AUDIT_LOG_INTEGRITY_FAIL: Failed verification (integrity or corruption issue)
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
  fssBasePath =
    if config.ghaf.type == "host" then "/persist/common/journal-fss" else "/etc/common/journal-fss";
  verifyClassifierLib = builtins.readFile ./fss-verify-classifier.sh;

  # Script to setup FSS keys on first boot
  setupScript = pkgs.writeShellApplication {
    name = "journal-fss-setup";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
      gawk
      findutils
    ];
    text = ''
      export LC_ALL=C

      ${verifyClassifierLib}

      KEY_DIR="${cfg.keyPath}"
      INIT_FILE="$KEY_DIR/initialized"
      VERIFY_KEY_FILE="$KEY_DIR/verification-key"
      MACHINE_ID=$(cat /etc/machine-id)
      STATE_DIR="/var/log/journal/$MACHINE_ID"
      PRE_FSS_ARCHIVE_FILE="$STATE_DIR/fss-pre-fss-archive"

      clear_initialized_state() {
        rm -f "$INIT_FILE"
      }

      publish_setup_state() {
        touch "$INIT_FILE"
        chmod 0644 "$INIT_FILE"
        # Write config pointer so test scripts can discover KEY_DIR without hostname
        printf '%s\n' "$KEY_DIR" > "$STATE_DIR/fss-config"
        chmod 0644 "$STATE_DIR/fss-config"
      }

      write_pre_fss_archive_record() {
        local archive_path="$1"

        rm -f "$PRE_FSS_ARCHIVE_FILE"
        if [ -n "$archive_path" ]; then
          printf '%s\n' "$archive_path" > "$PRE_FSS_ARCHIVE_FILE"
          chmod 0644 "$PRE_FSS_ARCHIVE_FILE"
        fi
      }

      list_archived_system_journals() {
        local journal_dir="$1"

        find "$journal_dir" -maxdepth 1 -type f -name 'system@*.journal' -print 2>/dev/null | sort
      }

      record_rotated_pre_fss_archive() {
        local before_file="$1"
        local journal_dir="$2"
        local archive_path=""
        local candidate=""
        local after_file

        after_file=$(mktemp)
        list_archived_system_journals "$journal_dir" > "$after_file"

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          if [ -z "$archive_path" ]; then
            continue
          fi

          if ! grep -Fxq "$archive_path" "$before_file"; then
            if [ -n "$candidate" ]; then
              fss_log warn "Multiple new archived system journals detected after rotation; not recording pre-FSS archive."
              candidate=""
              break
            fi

            candidate="$archive_path"
          fi
        done < "$after_file"

        rm -f "$after_file"
        write_pre_fss_archive_record "$candidate"
      }

      backfill_pre_fss_archive_if_missing() {
        local journal_dir="$1"
        local archive_path=""
        local candidate=""
        local matching_count=0
        local marker_mtime=""
        local archive_mtime=""
        local delta=0
        local mtime_tolerance_sec=2

        if [ -s "$PRE_FSS_ARCHIVE_FILE" ]; then
          return 0
        fi

        marker_mtime=$(stat -c %Y "$STATE_DIR/fss-rotated" 2>/dev/null || true)
        if [ -z "$marker_mtime" ]; then
          fss_log warn "Unable to read fss-rotated timestamp; not backfilling pre-FSS archive metadata."
          return 0
        fi

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          if [ -z "$archive_path" ]; then
            continue
          fi

          archive_mtime=$(stat -c %Y "$archive_path" 2>/dev/null || true)
          if [ -z "$archive_mtime" ]; then
            continue
          fi

          delta=$((archive_mtime - marker_mtime))
          if [ "$delta" -lt 0 ]; then
            delta=$((0 - delta))
          fi

          if [ "$delta" -le "$mtime_tolerance_sec" ]; then
            matching_count=$((matching_count + 1))
            if [ "$matching_count" -gt 1 ]; then
              fss_log warn "Multiple archived system journals match the FSS rotation timestamp; not backfilling pre-FSS archive metadata."
              return 0
            fi

            candidate="$archive_path"
          fi
        done < <(list_archived_system_journals "$journal_dir")

        if [ "$matching_count" -eq 1 ] && [ -n "$candidate" ]; then
          fss_log info "Backfilling recorded pre-FSS archive metadata for $candidate"
          write_pre_fss_archive_record "$candidate"
          return 0
        fi

        fss_log warn "No archived system journal matches the FSS rotation timestamp; not backfilling pre-FSS archive metadata."
      }

      rotate_to_clean_fss_state() {
        local journal_dir="$1"
        local sealing_key_file="$2"
        local rotated_marker="$STATE_DIR/fss-rotated"
        local before_file
        local marker_mtime=""
        local key_mtime=""

        marker_mtime=$(stat -c %Y "$rotated_marker" 2>/dev/null || true)
        key_mtime=$(stat -c %Y "$sealing_key_file" 2>/dev/null || true)

        if [ -n "$marker_mtime" ] && [ -n "$key_mtime" ] && [ "$marker_mtime" -ge "$key_mtime" ]; then
          backfill_pre_fss_archive_if_missing "$journal_dir"
          return 0
        fi

        before_file=$(mktemp)
        list_archived_system_journals "$journal_dir" > "$before_file"
        fss_log info "Rotating journal to ensure clean FSS state..."
        journalctl --rotate 2>/dev/null || true
        record_rotated_pre_fss_archive "$before_file" "$journal_dir"
        rm -f "$before_file"
        touch "$rotated_marker"
        chmod 0644 "$rotated_marker"
      }

      restart_journald_for_fss_activation() {
        # Journald only loads the FSS sealing key at startup. If setup previously
        # failed before this restart, later retries must still reload journald.
        fss_log info "Restarting journald to enable sealing..."
        if ! systemctl restart systemd-journald; then
          fss_log warn "Journald restart failed - sealing may not be active"
        fi
      }

      ensure_verification_key_ready() {
        local verify_key

        if [ ! -s "$VERIFY_KEY_FILE" ]; then
          fss_log fail "FSS verification key is missing or empty at $VERIFY_KEY_FILE"
          return 1
        fi

        if [ ! -r "$VERIFY_KEY_FILE" ]; then
          fss_log fail "FSS verification key is unreadable at $VERIFY_KEY_FILE"
          return 1
        fi

        verify_key=$(tr -d '[:space:]' < "$VERIFY_KEY_FILE")
        case "$verify_key" in
          */*) ;;
          *)
            fss_log fail "FSS verification key is malformed at $VERIFY_KEY_FILE"
            return 1
            ;;
        esac

        chmod 0400 "$VERIFY_KEY_FILE"
      }

      # Support both persistent and volatile storage
      FSS_KEY_FILE="/var/log/journal/$MACHINE_ID/fss"
      if [ ! -f "$FSS_KEY_FILE" ] && [ -f "/run/log/journal/$MACHINE_ID/fss" ]; then
        FSS_KEY_FILE="/run/log/journal/$MACHINE_ID/fss"
        fss_log info "Using volatile storage location for FSS keys"
      fi
      JOURNAL_DIR=$(dirname "$FSS_KEY_FILE")

      # Create key directory if it doesn't exist
      mkdir -p "$KEY_DIR"
      chmod 0700 "$KEY_DIR"

      # Ensure journal directory exists (for persistent storage)
      mkdir -p "$STATE_DIR"
      # Set permissions if possible (may fail in restricted environments like MicroVMs)
      chmod 0755 "/var/log/journal" 2>/dev/null || true
      chmod 2755 "$STATE_DIR" 2>/dev/null || true

      # Check if FSS keys already exist
      if [ -f "$FSS_KEY_FILE" ]; then
        fss_log info "FSS sealing key already exists at $FSS_KEY_FILE"
        if ! ensure_verification_key_ready; then
          # Keep sentinel so verify service can detect and alert on KEY_MISSING periodically
          fss_log warn "Verification key missing but sealing key present. Verify service will alert."
          publish_setup_state
          exit 1
        fi
        fss_log info "Setup already complete, verification key present, creating sentinel file"
        publish_setup_state
        if [ ! -f "$STATE_DIR/fss-rotated" ]; then
          restart_journald_for_fss_activation
        fi
        # One-time rotation to move pre-FSS entries to archive (fixes "Bad message")
        rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE"
        exit 0
      fi

      # Generate new FSS keys
      fss_log info "Setting up Forward Secure Sealing keys..."
      clear_initialized_state
      if ! journalctl --setup-keys --interval="${cfg.sealInterval}" > "$KEY_DIR/setup-output.txt" 2>&1; then
        fss_log fail "journalctl --setup-keys failed"
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
          fss_log pass "FSS verification key extracted successfully"
          fss_log info "IMPORTANT: Store verification key off-host in a secure vault"
        else
          fss_log warn "Verification key file is empty"
        fi
      else
        fss_log warn "Could not extract verification key from output"
      fi

      # Securely remove setup output (contains sensitive key material)
      shred -u "$KEY_DIR/setup-output.txt" 2>/dev/null || rm -f "$KEY_DIR/setup-output.txt"

      # Verify sealing key was created
      if [ ! -f "$FSS_KEY_FILE" ]; then
        clear_initialized_state
        fss_log fail "FSS key generation failed - key file not found at $FSS_KEY_FILE"
        exit 1
      fi

      if ! ensure_verification_key_ready; then
        # The sealing key exists now, so keep verify enabled to emit KEY_MISSING
        # even when verification key export failed during initial setup.
        fss_log warn "Verification key missing after key generation. Verify service will alert."
        restart_journald_for_fss_activation
        rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE"
        publish_setup_state
        exit 1
      fi

      # Restart journald to pick up the new FSS key
      # Journald only checks for FSS keys at startup, so rotation alone is insufficient
      restart_journald_for_fss_activation

      # Rotate so active journal starts clean with FSS (pre-FSS entries become archive)
      rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE"

      # Create sentinel file to prevent re-initialization
      publish_setup_state

      fss_log pass "Forward Secure Sealing initialization complete"
      fss_log info "Sealing key: $FSS_KEY_FILE"
      fss_log info "Verification key: $VERIFY_KEY_FILE"
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
            ${verifyClassifierLib}

            audit_log() {
              printf '%s\n' "$2" | systemd-cat -t journal-fss -p "$1"
            }

            fss_log info "Verifying journal integrity with Forward Secure Sealing..."

            if ! journalctl --list-boots >/dev/null 2>&1; then
              fss_log info "No journals found to verify (normal on fresh boot)"
              exit 0
            fi

            VERIFY_KEY_FILE="${cfg.keyPath}/verification-key"
            if [ ! -s "$VERIFY_KEY_FILE" ] || [ ! -r "$VERIFY_KEY_FILE" ]; then
              audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: Journal verification key missing, empty, or unreadable [KEY_MISSING]"
              fss_log fail "Journal integrity verification: FAILED (verification key missing, empty, or unreadable at $VERIFY_KEY_FILE)"
              exit 1
            fi

            MACHINE_ID=$(cat /etc/machine-id)
            PRE_FSS_ARCHIVE_FILE="/var/log/journal/$MACHINE_ID/fss-pre-fss-archive"
            RECOVERY_ARCHIVES_FILE="/var/log/journal/$MACHINE_ID/fss-recovery-archives"
            VERIFY_KEY=$(cat "$VERIFY_KEY_FILE")

            VERIFY_EXIT=0
            VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?

            fss_classify_verify_output "$VERIFY_OUTPUT"
            fss_verify_policy_decision \
              "$(fss_read_recorded_pre_fss_archive "$PRE_FSS_ARCHIVE_FILE")" \
              "$(fss_read_recorded_archive_list "$RECOVERY_ARCHIVES_FILE")"

            case "$FSS_VERDICT" in
            fail)
              audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: Journal integrity verification FAILED [$FSS_VERDICT_TAGS]"
              fss_log fail "Journal integrity verification: FAILED ($FSS_VERDICT_REASON)"
              fss_log_block <<EOF
      Output: $VERIFY_OUTPUT
      EOF
              if [ "$FSS_KEY_PARSE_ERROR" = 1 ] || [ "$FSS_KEY_REQUIRED_ERROR" = 1 ]; then
                fss_log_block <<EOF
      The verification key is missing, malformed, or unreadable by journalctl.
      To recover:
        1. rm ${cfg.keyPath}/initialized && rm /var/log/journal/*/fss
        2. Reboot to regenerate keys
        3. Back up the new ${cfg.keyPath}/verification-key
      EOF
              fi
              exit 1
              ;;
            partial)
              audit_log warning "WARNING: Journal integrity verification PARTIAL [$FSS_VERDICT_TAGS]"
              fss_log warn "Journal integrity verification: PARTIAL ($FSS_VERDICT_REASON)"
              fss_log_block <<EOF
      Output: $VERIFY_OUTPUT
      EOF
              exit 0
              ;;
            pass)
              audit_log info "AUDIT_LOG_VERIFY_COMPLETED: Journal integrity verification passed"
              if [ -n "$FSS_VERDICT_REASON" ]; then
                fss_log pass "Journal integrity verification: PASSED ($FSS_VERDICT_REASON)"
              else
                fss_log pass "Journal integrity verification: PASSED"
              fi
              if [ "$VERIFY_EXIT" -ne 0 ]; then
                fss_log info "Note: journalctl --verify returned exit $VERIFY_EXIT without critical errors [$FSS_VERDICT_TAGS]"
              fi
              exit 0
              ;;
            esac
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
        in
        "${fssBasePath}/${componentName}";
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
    # FSS requires audit to be enabled, so we use mkForce to ensure it's on
    # regardless of profile settings (audit is fundamental to FSS functionality)
    ghaf.security.audit.enable = lib.mkForce true;

    # Create key directory and journal directory via tmpfiles
    # Note: In VMs, ${cfg.keyPath} is a virtiofs mount point, so we only create it on host
    systemd = {
      tmpfiles.rules =
        lib.optionals (config.ghaf.type == "host") [
          "d /persist/common/journal-fss 0755 root root - -"
          "d ${cfg.keyPath} 0700 root root - -"
        ]
        ++ [
          "d /var/log/journal 0755 root systemd-journal - -"
        ];

      # One-shot service to generate FSS keys on first boot
      # Runs after journald is ready, then restarts journald to enable sealing
      services.journal-fss-setup = {
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
      services.journal-fss-verify = {
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
      timers.journal-fss-verify = {
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
    };

    # Audit rules to monitor FSS key and journal access
    ghaf.security.audit.extraRules = [
      # Monitor shared FSS key tree.
      "-w ${fssBasePath} -p wa -k journal_fss_keys"
      # Monitor sealed journal logs for tampering attempts
      "-w /var/log/journal -p wa -k journal_sealed_logs"
      # Monitor machine-id reads (critical for journal path resolution)
      "-w /etc/machine-id -p r -k machine_id_read"
    ];
  };
}
