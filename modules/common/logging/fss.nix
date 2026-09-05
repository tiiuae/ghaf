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
# Caveats (per-boot activation boundary, ghaf.logging.fss.activation):
# - Unsealed boot window: With activation enabled (default), entries written
#   before sealing is activated after clock readiness are collected but NOT
#   FSS-trusted. They are recorded as content-bound lifecycle receipts and
#   verification surfaces a matching current-boot receipt as a warning (never
#   a silent pass, since receipts are unauthenticated root-writable files); a
#   pre-activation archive failing verification for an earlier boot is also a
#   warning, while one whose content no longer matches its receipt fails closed.
# - Clock readiness is a boot gate and mitigation, not a trusted/authoritative
#   time source. On offline devices activation occurs on an unsynchronised clock.
# - FSS is a local primitive: it does not by itself defend against whole-file
#   deletion, mutable-verification-key replacement, or cross-component ordering.
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
  options,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    getExe
    optionalAttrs
    ;
  cfg = config.ghaf.logging.fss;
  clockReadyEnabled =
    cfg.enable && config.ghaf.logging.recovery.enable && config.ghaf.logging.recovery.clockReady.enable;
  activationEnabled = cfg.activation.enable;
  loggingEnabled = config.ghaf.logging.enable;
  hasPersistentJournalStorage = config.ghaf.type == "host" || config.ghaf.storagevm.enable;
  hasStructuredJournald = options.services.journald ? settings;
  hostPersistentJournalPath = "/persist/var/log/journal";
  fssBasePath =
    if config.ghaf.type == "host" then "/persist/common/journal-fss" else "/etc/common/journal-fss";
  fssTriagePackage =
    pkgs.fss-triage or (pkgs.callPackage ../../../packages/pkgs-by-name/fss-triage/package.nix { });

  preparePersistentJournalScript = pkgs.writeShellApplication {
    name = "journal-fss-prepare-persistent-journal";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      install -d -m 0755 /persist /persist/var /persist/var/log
      install -d -m 2755 -o root -g systemd-journal ${hostPersistentJournalPath}
      install -d -m 2755 -o root -g systemd-journal /var/log/journal
    '';
  };

  # Script to setup FSS keys on first boot
  setupScript = pkgs.writeShellApplication {
    name = "journal-fss-setup";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
      gawk
      findutils
      gnugrep
      util-linux
    ];
    # /etc/fss-verify-classifier.sh is populated at runtime (see environment.etc
    # below); shellcheck cannot follow it statically.
    excludeShellChecks = [ "SC1091" ];
    text = ''
      export LC_ALL=C

      source /etc/fss-verify-classifier.sh

      KEY_DIR="${cfg.keyPath}"
      INIT_FILE="$KEY_DIR/initialized"
      VERIFY_KEY_FILE="$KEY_DIR/verification-key"
      MACHINE_ID=$(cat /etc/machine-id)
      STATE_DIR="/var/log/journal/$MACHINE_ID"
      PRE_FSS_ARCHIVE_FILE="$STATE_DIR/fss-pre-fss-archive"
      RECOVERY_RECEIPTS_FILE="$STATE_DIR/fss-recovery-receipts"
      PRE_ACTIVATION_RECEIPTS_FILE="$STATE_DIR/fss-pre-activation-receipts"
      UNCLEAN_SHUTDOWN_RECEIPTS_FILE="$STATE_DIR/fss-unclean-shutdown-receipts"
      ACTIVATION_STATE_FILE="$STATE_DIR/fss-activation-state"
      FSS_BOOT_BASELINE_FILE="$STATE_DIR/fss-baseline-boot"
      CLOCK_JUMP_STAMP_FILE="$STATE_DIR/fss-clock-jump-attested"
      REKEY_COUNT_FILE="$STATE_DIR/fss-rekey-count"
      LIVE_PROBE_STATE_FILE="$STATE_DIR/fss-live-probe-state"
      ACTIVATION_ENABLED="${if activationEnabled then "1" else "0"}"
      REKEY_ENABLED="${if cfg.rekey.enable then "1" else "0"}"
      REKEY_ATTESTATION_TTL="${toString cfg.rekey.attestationValiditySeconds}"
      REKEY_MAX_ATTEMPTS="${toString cfg.rekey.maxAttempts}"
      REKEY_ATTEMPT_WINDOW="${toString cfg.rekey.attemptWindowSeconds}"
      REKEY_RETAINED_KEYS="${toString cfg.rekey.retainedKeys}"
      REKEY_HISTORY_FILE="$KEY_DIR/rekey-history"
      PRE_ACTIVATION_MAX_RECEIPTS="${toString cfg.activation.maxReceipts}"
      RECOVERY_MAX_RECEIPTS="${toString config.ghaf.logging.recovery.maxReceipts}"
      UNCLEAN_SHUTDOWN_MAX_RECEIPTS="${toString cfg.uncleanShutdown.maxReceipts}"
      ACTIVATION_FAILED=0
      ACTIVATION_RESTARTED_THIS_RUN=0
      RECORD_PRE_ACTIVATION_THIS_RUN=0
      SETUP_ARCHIVES_BEFORE=""
      JOURNALD_RUNTIME_CONF_DIR="/run/systemd/journald.conf.d"
      JOURNALD_FSS_RUNTIME_CONF="$JOURNALD_RUNTIME_CONF_DIR/90-ghaf-fss-activation.conf"

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

      receipt_file_has_path() {
        local receipt_file="$1"
        local needle="$2"

        [ -n "$needle" ] && [ -f "$receipt_file" ] || return 1
        awk -F '\t' -v p="$needle" '$2 == p { found = 1 } END { exit found ? 0 : 1 }' \
          "$receipt_file"
      }

      pre_activation_receipt_has_path() {
        local needle="$1"

        receipt_file_has_path "$PRE_ACTIVATION_RECEIPTS_FILE" "$needle"
      }

      record_recovery_receipt() {
        local archive_path="$1"
        local reason="''${2:-clock-jump-recovery}"

        [ -n "$archive_path" ] || return 0
        [ -s "$PRE_FSS_ARCHIVE_FILE" ] && [ "$(tr -d '[:space:]' < "$PRE_FSS_ARCHIVE_FILE")" = "$archive_path" ] && return 0
        if pre_activation_receipt_has_path "$archive_path"; then
          return 0
        fi
        if receipt_file_has_path "$RECOVERY_RECEIPTS_FILE" "$archive_path"; then
          return 0
        fi

        fss_write_receipt \
          "$RECOVERY_RECEIPTS_FILE" \
          "$archive_path" \
          "$reason" \
          info \
          "Recorded FSS recovery archive receipt"
      }

      # Record a content-bound lifecycle receipt for an archive rotated away at
      # the per-boot activation boundary, so the verifier recognises an expected
      # "insecure boot logs" exception by identity, not by path string alone.
      # Schema is defined in fss-verify-classifier.sh (FSS_RECEIPT_SCHEMA_VERSION).
      record_pre_activation_receipt() {
        local archive_path="$1"
        local reason="''${2:-pre-activation-rotation}"
        fss_write_receipt \
          "$PRE_ACTIVATION_RECEIPTS_FILE" \
          "$archive_path" \
          "$reason" \
          warn \
          "Recorded insecure pre-activation journal receipt"
      }

      # Record content-bound receipts for journals that JOURNALD ITSELF reported as
      # "corrupted or uncleanly shut down" in the current boot's log and renamed to
      # <path>~. That message is journald's own attestation of a prior unclean kill
      # (host crash, power loss, stop-timeout SIGKILL) — the unpreventable residual.
      # The verifier treats a content-matched unclean receipt as a warning; an
      # unmatched .journal~ or the live system.journal still fails closed. See
      # fss-verify-classifier.sh policy.
      record_unclean_shutdown_receipt() {
        local archive_path="$1"
        fss_write_receipt \
          "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" \
          "$archive_path" \
          "unclean-shutdown" \
          warn \
          "Recorded unclean-shutdown journal receipt"
      }

      # Journal paths journald named as uncleanly shut down in the current boot.
      # journalctl --grep needs PCRE2, which the deployed journalctl is built
      # without ("PCRE2 support is not compiled in") -- it then exits non-zero
      # having matched nothing, silently disabling this detection. Filter the
      # plain output with grep -F instead.
      unclean_shutdown_named_paths() {
        journalctl -b -u systemd-journald.service \
          --output=cat --quiet --no-pager 2>/dev/null \
          | { grep -F "corrupted or uncleanly shut down, renaming and replacing" || true; } \
          | { grep -oE '/var/log/journal/[^ ]+\.journal' || true; } \
          | sort -u
      }

      # For each journald-attested unclean path P, receipt its renamed corpse "P~"
      # only if it exists on disk (record_lifecycle_receipt is content-bound and
      # skips a missing file). The target always ends in '~', so it can never be the
      # live system.journal — the active journal is never receipted here.
      record_unclean_shutdown_journals() {
        local named_path target
        while IFS= read -r named_path || [ -n "$named_path" ]; do
          [ -n "$named_path" ] || continue
          target="''${named_path}~"
          [ -f "$target" ] || continue
          record_unclean_shutdown_receipt "$target"
        done < <(unclean_shutdown_named_paths)
      }

      prune_pre_activation_receipts() {
        fss_prune_receipt_file "$PRE_ACTIVATION_RECEIPTS_FILE" "$PRE_ACTIVATION_MAX_RECEIPTS" "Pre-activation"
      }

      prune_recovery_receipts() {
        fss_prune_receipt_file "$RECOVERY_RECEIPTS_FILE" "$RECOVERY_MAX_RECEIPTS" "Recovery"
      }

      prune_unclean_shutdown_receipts() {
        fss_prune_receipt_file "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" "$UNCLEAN_SHUTDOWN_MAX_RECEIPTS" "Unclean-shutdown"
      }

      record_fss_archive_metadata() {
        local archive_path="$1"
        local may_record_pre_fss_archive="''${2:-0}"

        if [ "$may_record_pre_fss_archive" = 1 ]; then
          if [ ! -s "$PRE_FSS_ARCHIVE_FILE" ]; then
            write_pre_fss_archive_record "$archive_path"
          else
            record_recovery_receipt "$archive_path" "setup-recovery"
          fi
          return 0
        fi

        if [ ! -s "$PRE_FSS_ARCHIVE_FILE" ]; then
          fss_log warn "Pre-FSS archive metadata missing; not recording setup rotation as pre-FSS archive: $archive_path"
          return 0
        fi

        fss_log info "Pre-FSS archive already recorded; not adding setup rotation to recovery allowlist: $archive_path"
      }

      list_archived_system_journals() {
        local journal_dir="$1"

        find "$journal_dir" -maxdepth 1 -type f -name 'system@*.journal' -print 2>/dev/null | sort
      }

      # Archived system journals only: user and temp failures warn regardless of
      # the allowlist, so receipting them just consumes the bounded store. "~" is
      # journald's disposed-ARCHIVE name, so the live journal cannot match.
      list_time_jump_receiptable_journals() {
        local journal_dir="$1"

        find "$journal_dir" -maxdepth 1 -type f \
          \( -name 'system@*.journal' -o -name 'system@*.journal~' \) \
          -print 2>/dev/null | sort -u
      }

      boot_start_epoch() {
        awk -v now="$(date +%s)" '{printf "%d\n", now - $1}' /proc/uptime
      }

      write_boot_baseline_record() {
        printf '%s\n' "$(fss_current_boot_id)" > "$FSS_BOOT_BASELINE_FILE"
        chmod 0644 "$FSS_BOOT_BASELINE_FILE"
      }

      boot_baseline_current() {
        [ -s "$FSS_BOOT_BASELINE_FILE" ] || return 1
        [ "$(tr -d '[:space:]' < "$FSS_BOOT_BASELINE_FILE")" = "$(fss_current_boot_id)" ]
      }

      # Not journalctl --grep: the deployed journalctl has no PCRE2, so it
      # matched nothing and silently disabled this. Filtering now lives in
      # fss_time_jump_epochs_from_lines. journalctl stays guarded because the
      # caller assigns this in a command substitution under errexit.
      current_boot_time_jump_epochs() {
        { journalctl -b -u systemd-journald.service \
          --output=short-unix \
          --quiet \
          --no-pager 2>/dev/null || true; } \
          | fss_time_jump_epochs_from_lines
      }

      # Persist journald's attestation of a backward step. A poisoned sealing
      # epoch usually surfaces on the boot AFTER the jump, when `journalctl -b`
      # no longer shows one. ghaf-clock-jump-watcher writes the same stamp.
      record_clock_jump_attestation() {
        local epochs

        epochs="$(current_boot_time_jump_epochs)"
        [ -n "$epochs" ] || return 0
        printf '%s\t%s\t%s\n' \
          "$(date +%s)" \
          "$(fss_current_boot_id)" \
          "$(printf '%s' "$epochs" | tr '\n' ',')" \
          > "$CLOCK_JUMP_STAMP_FILE"
        chmod 0644 "$CLOCK_JUMP_STAMP_FILE"
      }

      # Whether journald attested a backward step recently enough to authorise
      # discarding the key pair. Only reached after the future-tag gate, so the
      # history scan below never runs on a healthy boot.
      clock_jump_attested() {
        local now state epochs

        now=$(date +%s)

        if [ -n "$(current_boot_time_jump_epochs)" ]; then
          fss_log info "Clock-jump attestation: journald attested a backward step this boot"
          return 0
        fi

        state=$(fss_clock_jump_stamp_state \
          "$(head -n1 "$CLOCK_JUMP_STAMP_FILE" 2>/dev/null || true)" \
          "$(fss_current_boot_id)" "$now" "$REKEY_ATTESTATION_TTL")
        case "$state" in
        current-boot | persisted-stamp)
          fss_log info "Clock-jump attestation: accepted from $state"
          return 0
          ;;
        malformed | expired)
          fss_log warn "Clock-jump attestation: discarding $state stamp $CLOCK_JUMP_STAMP_FILE"
          rm -f "$CLOCK_JUMP_STAMP_FILE"
          ;;
        esac

        # First jump on a machine whose watcher never ran: no stamp, and the
        # attestation sits in an earlier boot's journal. Bounded by the window.
        epochs=$({ journalctl -u systemd-journald.service \
          --since="@$(( now - REKEY_ATTESTATION_TTL ))" \
          --output=short-unix \
          --quiet \
          --no-pager 2>/dev/null || true; } | fss_time_jump_epochs_from_lines)
        if [ -n "$epochs" ]; then
          fss_log info "Clock-jump attestation: found in journal history within the last ''${REKEY_ATTESTATION_TTL}s"
          return 0
        fi

        return 1
      }

      # Cross-invocation bound on re-keying. FSS_REKEY_ATTEMPTED only bounds one
      # exec chain, and the watcher restarts setup on every new attestation.
      rekey_attempt_budget_available() {
        local record first count now

        now=$(date +%s)
        record=$(head -n1 "$REKEY_COUNT_FILE" 2>/dev/null || true)
        first=""
        count=0
        [ -z "$record" ] || IFS=$'\t' read -r first count <<< "$record"
        case "$first" in "" | *[!0-9]*) first="" ;; esac
        case "$count" in "" | *[!0-9]*) count=0 ;; esac

        # Either direction: a backward step can leave the start in the future.
        if [ -z "$first" ] \
          || [ "$(( now - first ))" -gt "$REKEY_ATTEMPT_WINDOW" ] \
          || [ "$(( first - now ))" -gt "$REKEY_ATTEMPT_WINDOW" ]; then
          first="$now"
          count=0
        fi

        if [ "$count" -ge "$REKEY_MAX_ATTEMPTS" ]; then
          fss_log fail "FSS re-key refused: $count automatic re-keys already within ''${REKEY_ATTEMPT_WINDOW}s (limit $REKEY_MAX_ATTEMPTS)"
          fss_log fail "Sealing stays broken and visible rather than re-keying in a loop."
          fss_log fail "Investigate, then clear $REKEY_COUNT_FILE to allow another attempt."
          return 1
        fi

        printf '%s\t%s\n' "$first" "$(( count + 1 ))" > "$REKEY_COUNT_FILE"
        chmod 0644 "$REKEY_COUNT_FILE"
      }

      record_current_boot_time_jump_archives() {
        local journal_dir="$1"
        local cutoff_epoch="$2"
        local boot_epoch archive_path archive_mtime time_jump_epochs

        time_jump_epochs="$(current_boot_time_jump_epochs)"
        [ -n "$time_jump_epochs" ] || return 0
        boot_epoch="$(boot_start_epoch)"

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          [ -n "$archive_path" ] || continue
          if [ "$ACTIVATION_ENABLED" = 1 ]; then
            [ -n "$SETUP_ARCHIVES_BEFORE" ] && [ -f "$SETUP_ARCHIVES_BEFORE" ] || continue
            grep -Fxq "$archive_path" "$SETUP_ARCHIVES_BEFORE" 2>/dev/null || continue
          fi
          archive_mtime=$(stat -c %Y "$archive_path" 2>/dev/null || true)
          [ -n "$archive_mtime" ] || continue

          if [ "$archive_mtime" -ge "$boot_epoch" ] \
            && [ "$archive_mtime" -le "$cutoff_epoch" ] \
            && fss_mtime_matches_time_jump_epoch "$archive_mtime" "$time_jump_epochs"; then
            if [ "$ACTIVATION_ENABLED" = 1 ]; then
              record_pre_activation_receipt "$archive_path" "pre-activation-time-jump"
            else
              record_recovery_receipt "$archive_path" "clock-jump-recovery"
            fi
          fi
        done < <(list_time_jump_receiptable_journals "$journal_dir")
      }

      # Receipt archived system journals that newly appeared immediately after the
      # activation restart, comparing against a snapshot taken at the start of the
      # setup run (SETUP_ARCHIVES_BEFORE). Rotation candidates are receipted by
      # record_rotated_fss_archive. Crucially, a pre-existing archive that fails
      # verification — e.g. a tampered post-activation one — was present before
      # the run, so it is NOT receipted and still fails closed.
      record_setup_run_pre_activation_archives() {
        local journal_dir="$1"
        local archive_path

        [ "$ACTIVATION_ENABLED" = 1 ] || return 0
        [ "$RECORD_PRE_ACTIVATION_THIS_RUN" = 1 ] || return 0
        [ -n "$SETUP_ARCHIVES_BEFORE" ] && [ -f "$SETUP_ARCHIVES_BEFORE" ] || return 0

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          [ -n "$archive_path" ] || continue
          grep -Fxq "$archive_path" "$SETUP_ARCHIVES_BEFORE" 2>/dev/null && continue
          record_pre_activation_receipt "$archive_path" "pre-activation-restart"
        done < <(list_archived_system_journals "$journal_dir")
      }

      harden_sealing_key() {
        local sealing_key_file="$1"

        [ -f "$sealing_key_file" ] || return 0
        chown root:root "$sealing_key_file" 2>/dev/null || true
        chmod 0600 "$sealing_key_file" 2>/dev/null || true
      }

      record_rotated_fss_archive() {
        local before_file="$1"
        local journal_dir="$2"
        local may_record_pre_fss_archive="''${3:-0}"
        local archive_path=""
        local candidate=""
        local candidate_count=0
        local after_file

        after_file=$(mktemp)
        list_archived_system_journals "$journal_dir" > "$after_file"

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          if [ -z "$archive_path" ]; then
            continue
          fi

          if ! grep -Fxq "$archive_path" "$before_file"; then
            if [ "$RECORD_PRE_ACTIVATION_THIS_RUN" = 1 ]; then
              record_pre_activation_receipt "$archive_path" "pre-activation-rotation"
            fi

            candidate_count=$((candidate_count + 1))
            candidate="$archive_path"
          fi
        done < "$after_file"

        rm -f "$after_file"
        [ "$candidate_count" -gt 0 ] || return 0

        if [ "$candidate_count" -gt 1 ]; then
          fss_log warn "Multiple new archived system journals detected after rotation; not recording pre-FSS archive."
          return 0
        fi

        if [ "$ACTIVATION_ENABLED" = 1 ] && [ "$may_record_pre_fss_archive" = 1 ] && [ -s "$PRE_FSS_ARCHIVE_FILE" ]; then
          fss_log info "Pre-FSS archive already recorded; not adding activation rotation to recovery allowlist: $candidate"
          return 0
        fi

        record_fss_archive_metadata "$candidate" "$may_record_pre_fss_archive"
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
        local force_rotation="''${3:-0}"
        local rotated_marker="$STATE_DIR/fss-rotated"
        local before_file
        local marker_mtime=""
        local key_mtime=""
        local may_record_pre_fss_archive=0
        local rotation_started=""

        if [ "$ACTIVATION_ENABLED" = 1 ] && [ "$ACTIVATION_FAILED" = 1 ]; then
          fss_log warn "Skipping FSS cleanup rotation because sealing activation failed"
          return 0
        fi

        # Receipt any journals journald attested as uncleanly shut down this boot.
        # Runs every setup invocation (dedup-safe); skipped above on activation
        # failure so we never receipt anything when sealing did not take effect.
        record_unclean_shutdown_journals

        marker_mtime=$(stat -c %Y "$rotated_marker" 2>/dev/null || true)
        key_mtime=$(stat -c %Y "$sealing_key_file" 2>/dev/null || true)
        if [ "$force_rotation" = 1 ] || [ -z "$marker_mtime" ]; then
          may_record_pre_fss_archive=1
        fi

        if [ "$force_rotation" != 1 ] \
          && [ "$ACTIVATION_RESTARTED_THIS_RUN" != 1 ] \
          && activation_boundary_complete_current_boot \
          && [ -n "$marker_mtime" ]; then
          backfill_pre_fss_archive_if_missing "$journal_dir"
          return 0
        fi

        if [ "$force_rotation" != 1 ] \
          && [ "$ACTIVATION_RESTARTED_THIS_RUN" != 1 ] \
          && activation_state_record_current_boot \
          && [ "$RECORD_PRE_ACTIVATION_THIS_RUN" != 1 ] \
          && [ -n "$marker_mtime" ]; then
          backfill_pre_fss_archive_if_missing "$journal_dir"
          fss_log info "Restoring current boot FSS baseline without post-activation rotation"
          write_boot_baseline_record
          return 0
        fi

        if [ "$force_rotation" != 1 ] && [ -n "$marker_mtime" ]; then
          backfill_pre_fss_archive_if_missing "$journal_dir"
        fi

        if [ "$force_rotation" != 1 ] \
          && [ "$ACTIVATION_ENABLED" != 1 ] \
          && [ -n "$marker_mtime" ] \
          && [ -n "$key_mtime" ] \
          && [ "$marker_mtime" -ge "$key_mtime" ]; then
          return 0
        fi

        before_file=$(mktemp)
        list_archived_system_journals "$journal_dir" > "$before_file"
        rotation_started=$(date +%s)
        record_current_boot_time_jump_archives "$journal_dir" "$rotation_started"
        fss_log info "Rotating journal to ensure clean FSS state..."
        journalctl --rotate 2>/dev/null || true
        journalctl --sync 2>/dev/null || true
        record_rotated_fss_archive "$before_file" "$journal_dir" "$may_record_pre_fss_archive"
        rm -f "$before_file"
        touch "$rotated_marker"
        chmod 0644 "$rotated_marker"
        write_boot_baseline_record
      }

      write_activation_state() {
        printf '%s\t%s\n' "$1" "$(fss_current_boot_id)" > "$ACTIVATION_STATE_FILE"
        chmod 0644 "$ACTIVATION_STATE_FILE"
      }

      runtime_fss_activation_config_present() {
        [ -f "$JOURNALD_FSS_RUNTIME_CONF" ] \
          && grep -Fxq "Seal=yes" "$JOURNALD_FSS_RUNTIME_CONF"
      }

      activation_state_value() {
        [ -r "$ACTIVATION_STATE_FILE" ] || return 0
        awk -F '\t' 'NR == 1 { print $1 }' "$ACTIVATION_STATE_FILE"
      }

      activation_state_boot_id() {
        [ -r "$ACTIVATION_STATE_FILE" ] || return 0
        awk -F '\t' 'NR == 1 { print $2 }' "$ACTIVATION_STATE_FILE"
      }

      activation_state_record_current_boot() {
        [ "$(activation_state_value)" = "active" ] \
          && [ "$(activation_state_boot_id)" = "$(fss_current_boot_id)" ]
      }

      activation_boundary_complete_current_boot() {
        activation_state_record_current_boot \
          && boot_baseline_current
      }

      rotation_marker_present() {
        local marker_mtime

        marker_mtime=$(stat -c %Y "$STATE_DIR/fss-rotated" 2>/dev/null || true)
        [ -n "$marker_mtime" ]
      }

      activation_boundary_recording_needed() {
        [ "$ACTIVATION_ENABLED" = 1 ] || return 1
        ! activation_state_record_current_boot
      }

      journald_activation_already_current() {
        [ "$ACTIVATION_ENABLED" = 1 ] || return 1
        runtime_fss_activation_config_present \
          && activation_state_record_current_boot \
          && rotation_marker_present \
          && fss_sealing_active_in_config
      }

      # Restart journald so it loads the FSS sealing key, and (when activation is
      # enabled) confirm sealing actually took effect. Returns non-zero if the
      # runtime drop-in cannot be written, the restart fails, or sealing cannot be
      # confirmed afterwards, so the caller can fail the setup closed rather than
      # leaving an unsealed journal that looks "set up".
      restart_journald_for_fss_activation() {
        local restart_ok=1

        if [ "$ACTIVATION_ENABLED" = 1 ]; then
          if ! install -d -m 0755 "$JOURNALD_RUNTIME_CONF_DIR" \
            || ! printf '%s\n' '[Journal]' 'Seal=yes' > "$JOURNALD_FSS_RUNTIME_CONF"; then
            fss_log fail "Failed to write runtime journald FSS activation config: $JOURNALD_FSS_RUNTIME_CONF"
            write_activation_state failed
            return 1
          fi
          chmod 0644 "$JOURNALD_FSS_RUNTIME_CONF"
          fss_log info "Wrote runtime journald FSS activation config: $JOURNALD_FSS_RUNTIME_CONF"
        fi

        # Journald only loads the FSS sealing key at startup. If setup previously
        # failed before this restart, later retries must still reload journald.
        fss_log info "Restarting journald to enable sealing..."
        systemctl reset-failed \
          systemd-journald.service \
          systemd-journald.socket \
          systemd-journald-dev-log.socket \
          systemd-journald-audit.socket >/dev/null 2>&1 || true
        if ! systemctl restart systemd-journald; then
          fss_log fail "Journald restart failed - sealing may not be active"
          restart_ok=0
        fi

        if [ "$ACTIVATION_ENABLED" != 1 ]; then
          write_activation_state disabled
          return 0
        fi

        if [ "$restart_ok" = 1 ]; then
          # systemd-analyze cat-config queries the merged config right after
          # restarting journald; caught at exactly the wrong moment, it can
          # still read the pre-restart config and report Seal=no even though
          # journald picks up the runtime drop-in within a second or two.
          # Mirrors the re-verify-before-believing-it pattern already used for
          # live-journal counter mismatches: retry briefly rather than failing
          # the whole boot closed on a check taken too early.
          local confirm_attempt=1
          local confirm_retries=3
          while [ "$confirm_attempt" -le "$confirm_retries" ]; do
            if fss_sealing_active_in_config; then
              ACTIVATION_RESTARTED_THIS_RUN=1
              write_activation_state active
              fss_log info "Confirmed journald sealing is active after restart"
              return 0
            fi
            [ "$confirm_attempt" -eq "$confirm_retries" ] && break
            fss_log info "Sealing not yet confirmed on attempt $confirm_attempt; retrying"
            confirm_attempt=$((confirm_attempt + 1))
            sleep 1
          done
        fi

        fss_log fail "Journald sealing could not be confirmed after restart; failing closed"
        write_activation_state failed
        return 1
      }

      # Distinguish a diverged key pair from genuine journal damage.
      #
      # The active journal was created by the running journald moments ago and
      # sealed with the sealing key currently in use, so a tag failure on that
      # file *alone* cannot be pre-existing corruption -- it means the stored
      # verification key no longer corresponds to the sealing key.
      #
      # The two halves live in separate persistence domains: the verification
      # key under cfg.keyPath, the sealing key under the journal directory. They
      # can therefore be reset independently (re-provisioning, a stray
      # `journalctl --setup-keys`, a half-completed key rotation). Keys are only
      # ever generated together on the branch above, which is unreachable once a
      # sealing key exists, so nothing re-converges them: from the moment they
      # diverge every boot fails here. Reporting that plainly matters because
      # the raw journalctl output blames the journal contents, which sends
      # whoever reads it looking for disk corruption that is not there.
      #
      # Diagnosis only -- the verdict is unchanged and this still fails closed.
      verification_key_diverged_from_sealing_key() {
        local key="$1" active_journal probe_output probe_exit

        active_journal="$JOURNAL_DIR/system.journal"
        [ -f "$active_journal" ] || return 1

        probe_exit=0
        probe_output=$(journalctl --verify --verify-key="$key" \
          --file="$active_journal" 2>&1) || probe_exit=$?
        [ "$probe_exit" -eq 0 ] && return 1

        case "''${probe_output,,}" in
        *"tag failed verification"* | *"bad message"*) return 0 ;;
        *) return 1 ;;
        esac
      }

      # A backward realtime step after sealing leaves the FSPRG epoch ahead of
      # the wall clock: every entry sealed until real time catches up fails
      # with "Older entry after newer tag" -- including the freshly rotated
      # active journal -- so setup fails closed on every boot for the length
      # of the step, and the key-divergence diagnosis below misfires on it.
      # journald itself attests the jump ("Time jumped backwards, rotating"),
      # so this state is recoverable: freeze and receipt the sealed history,
      # discard the poisoned key pair, and re-run key setup from the current
      # clock. Bounded to one attempt per invocation chain, and only when the
      # future tag sits beyond any plausible in-flight sealing interval.
      # Superseded keys, newest first. Sorted on the epoch suffix, not the whole
      # path, so a dot in cfg.keyPath cannot reorder them.
      list_retained_verification_keys() {
        find "$KEY_DIR" -maxdepth 1 -type f -name 'verification-key.*' -print 2>/dev/null \
          | awk -F'verification-key.' '{ printf "%s\t%s\n", $NF, $0 }' \
          | sort -k1,1nr \
          | cut -f2-
      }

      # Keep the outgoing verification key: a re-key regenerates seed and
      # start_usec, so nothing sealed before it verifies under the new key.
      # Non-zero if retention failed, so the caller aborts before deleting the
      # sealing key.
      retain_previous_verification_key() {
        local rekey_epoch="$1" retained

        [ -s "$VERIFY_KEY_FILE" ] || return 0
        if [ "$REKEY_RETAINED_KEYS" -le 0 ]; then
          return 0
        fi

        retained="$KEY_DIR/verification-key.$rekey_epoch"
        if ! mv -f "$VERIFY_KEY_FILE" "$retained"; then
          fss_log fail "Could not retain the outgoing FSS verification key at $retained"
          fss_log fail "Refusing to re-key: that would leave pre-jump sealed history permanently unverifiable."
          return 1
        fi
        chown root:root "$retained" 2>/dev/null || true
        chmod 0400 "$retained" 2>/dev/null || true
        fss_log warn "Retained the superseded FSS verification key at $retained"
        return 0
      }

      prune_retained_verification_keys() {
        local kept=0 path

        while IFS= read -r path || [ -n "$path" ]; do
          [ -n "$path" ] || continue
          kept=$(( kept + 1 ))
          [ "$kept" -gt "$REKEY_RETAINED_KEYS" ] || continue
          rm -f "$path"
          fss_log info "Pruned superseded verification key $path (keeping newest $REKEY_RETAINED_KEYS)"
        done < <(list_retained_verification_keys)
      }

      # Append-only re-key log. A silent re-key invalidates the off-host copy of
      # the verification key that the keyPath docs tell operators to keep.
      record_rekey_history() {
        local rekey_epoch="$1" retained="$2" attestation="$3" retained_sha

        retained_sha=$(sha256sum "$retained" 2>/dev/null | cut -d' ' -f1 || true)
        printf '%s\t%s\t%s\t%s\n' \
          "$rekey_epoch" "$retained" "''${retained_sha:--}" "''${attestation:--}" \
          >> "$REKEY_HISTORY_FILE" 2>/dev/null || true
        chmod 0600 "$REKEY_HISTORY_FILE" 2>/dev/null || true
        printf '%s\n' \
          "AUDIT_LOG_FSS_REKEY: FSS re-keyed after an attested backward clock step at $rekey_epoch; superseded verification key retained at $retained" \
          | systemd-cat -t journal-fss -p crit 2>/dev/null || true
      }

      # Proof an archive belongs to a lineage sealed before the re-key. One
      # tampered with beforehand fails under the old key too, so is not excused.
      archive_verifies_under_retained_key() {
        local archive_path="$1" key_file key

        while IFS= read -r key_file || [ -n "$key_file" ]; do
          [ -n "$key_file" ] || continue
          [ -s "$key_file" ] && [ -r "$key_file" ] || continue
          key=$(tr -d '[:space:]' < "$key_file")
          if journalctl --verify --verify-key="$key" --file="$archive_path" >/dev/null 2>&1; then
            return 0
          fi
        done < <(list_retained_verification_keys)

        return 1
      }

      recover_from_time_poisoned_sealing() {
        local verify_output="$1" future_us now_us margin_us archive_path
        local rekey_epoch attestation_epoch retained
        local failing_paths before_file receipted

        [ "$REKEY_ENABLED" = 1 ] || return 1
        [ "''${FSS_REKEY_ATTEMPTED:-0}" = 0 ] || return 1
        now_us=$(( $(date +%s) * 1000000 ))
        margin_us=$(( 300 * 1000000 ))
        future_us=$(fss_time_poisoned_sealing_epoch_us "$verify_output" "$now_us" "$margin_us") \
          || return 1

        # A future tag alone is not evidence of a jump: B is derived entirely
        # from $VERIFY_KEY_FILE, so a far-future key makes every journal report
        # one -- and the response below is to delete both keys and excuse the
        # history. Require journald's own attestation first.
        if ! clock_jump_attested; then
          fss_log fail "Sealing epoch is $(( (future_us - now_us) / 1000000 ))s ahead of the wall clock, but journald never attested a backward clock step"
          fss_log fail "Refusing to re-key: verification stays failed rather than discarding the key pair on unverified evidence."
          fss_log fail "If the clock really did step back, re-provision the FSS state by hand."
          return 1
        fi
        rekey_attempt_budget_available || return 1

        fss_log warn "Sealing epoch is $(( (future_us - now_us) / 1000000 ))s ahead of the wall clock (journald-attested clock jump); recovering by re-keying FSS"
        rekey_epoch=$(date +%s)
        attestation_epoch=$(cut -f1 "$CLOCK_JUMP_STAMP_FILE" 2>/dev/null | head -n1 || true)

        # Before anything destructive: on failure nothing has been lost yet.
        retained="$KEY_DIR/verification-key.$rekey_epoch"
        retain_previous_verification_key "$rekey_epoch" || return 1

        # Open a re-key transaction: journals sealed under the discarded key
        # keep surfacing as failing archives for a while (frozen at the next
        # rotation or at shutdown), so the receipting below cannot be one-shot.
        # finish_setup reconciles against this stamp on every later run until
        # the transition window is clean, then closes it.
        printf '%s\n' "$rekey_epoch" > "$STATE_DIR/fss-rekey-epoch"
        chmod 0644 "$STATE_DIR/fss-rekey-epoch"

        # Receipt what the jump broke, not every archive: a blanket pass excuses
        # unrelated failures and can overrun recovery.maxReceipts, where one
        # eviction turns the unit red. Two sources, since the output predates
        # the rotation: what was failing, plus what the rotation froze.
        failing_paths=$(fss_unique_fail_paths_from_output "$verify_output")
        before_file=$(mktemp)
        list_time_jump_receiptable_journals "$JOURNAL_DIR" > "$before_file"
        journalctl --rotate 2>/dev/null || true
        journalctl --sync 2>/dev/null || true
        receipted=0
        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          [ -n "$archive_path" ] || continue
          if ! grep -Fxq "$archive_path" "$before_file" 2>/dev/null \
            || printf '%s\n' "$failing_paths" | grep -Fxq "$archive_path"; then
            record_recovery_receipt "$archive_path" "clock-jump-rekey"
            receipted=$(( receipted + 1 ))
          fi
        done < <(list_time_jump_receiptable_journals "$JOURNAL_DIR")
        rm -f "$before_file"
        if [ "$receipted" = 0 ]; then
          fss_log warn "Re-key receipted no archives; the freeze rotation may not have taken effect"
        fi
        prune_recovery_receipts
        rm -f "$FSS_KEY_FILE"
        record_rekey_history "$rekey_epoch" "$retained" "$attestation_epoch"
        prune_retained_verification_keys
        clear_initialized_state
        rm -f "$STATE_DIR/fss-rotated" "$ACTIVATION_STATE_FILE" "$FSS_BOOT_BASELINE_FILE"
        # Consume the attestation: it authorises exactly one re-key. Kept out of
        # the lifecycle wipe above because it is evidence, not lifecycle state.
        fss_log info "Consuming clock-jump attestation; it authorised this re-key and no further one"
        rm -f "$CLOCK_JUMP_STAMP_FILE"
        # exec skips the EXIT trap, so drop the tempfile here.
        cleanup_setup_tmp
        FSS_REKEY_ATTEMPTED=1 exec "$0"
      }

      write_live_probe_state() {
        printf '%s\t%s\n' "$(fss_current_boot_id)" "$1" > "$LIVE_PROBE_STATE_FILE"
        chmod 0644 "$LIVE_PROBE_STATE_FILE"
      }

      live_probe_unclean_this_boot() {
        local record boot result

        record=$(head -n1 "$LIVE_PROBE_STATE_FILE" 2>/dev/null || true)
        [ -n "$record" ] || return 1
        IFS=$'\t' read -r boot result <<< "$record"
        [ "$boot" = "$(fss_current_boot_id)" ] && [ "$result" = unclean ]
      }

      # Whether a re-entrant run has any reason to probe. With none it does not,
      # which is what keeps a journal-wide verify off every watcher trigger.
      live_probe_warranted() {
        if [ -f "$CLOCK_JUMP_STAMP_FILE" ] || [ -f "$STATE_DIR/fss-rekey-epoch" ]; then
          return 0
        fi
        # Sticky until a probe comes back clean.
        live_probe_unclean_this_boot
      }

      verify_live_sealing_after_activation() {
        local verify_key verify_output verify_exit marker probe_scope

        [ "$ACTIVATION_ENABLED" = 1 ] || return 0

        if [ "$ACTIVATION_RESTARTED_THIS_RUN" = 1 ]; then
          # Activation boundary, once per boot: verify everything, as before.
          probe_scope=full
        elif journald_activation_already_current && live_probe_warranted; then
          # Re-entrant run, typically the watcher. Probe the live journal
          # alone: a live poisoned epoch shows there by definition, and the
          # archived set is covered by the boundary probe and the verify timer.
          probe_scope=live
        else
          return 0
        fi

        [ "$ACTIVATION_FAILED" = 0 ] || return 1
        [ -s "$VERIFY_KEY_FILE" ] && [ -r "$VERIFY_KEY_FILE" ] || return 0

        marker="FSS activation live sealing probe $(fss_current_boot_id) $$"
        logger -t journal-fss "$marker" 2>/dev/null || true
        journalctl --sync 2>/dev/null || true

        verify_key=$(tr -d '[:space:]' < "$VERIFY_KEY_FILE")
        verify_exit=0
        if [ "$probe_scope" = live ]; then
          verify_output=$(journalctl --verify --verify-key="$verify_key" \
            --file="$JOURNAL_DIR/system.journal" 2>&1) || verify_exit=$?
        else
          verify_output=$(journalctl --verify --verify-key="$verify_key" 2>&1) || verify_exit=$?
        fi
        fss_classify_verify_output "$verify_output"

        if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] \
          || [ -n "$FSS_OTHER_FAILURES" ] \
          || [ "$FSS_KEY_PARSE_ERROR" = 1 ] \
          || [ "$FSS_KEY_REQUIRED_ERROR" = 1 ]; then
          # Checked before the key-divergence diagnosis: a time-poisoned
          # sealing epoch produces the same active-journal failure signature
          # and would be misreported as a diverged key pair. On success this
          # re-execs the setup script and does not return.
          recover_from_time_poisoned_sealing "$verify_output" || true
          if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] \
            && verification_key_diverged_from_sealing_key "$verify_key"; then
            fss_log fail "FSS verification key does not match the sealing key in use"
            fss_log fail "  verification key: $VERIFY_KEY_FILE"
            fss_log fail "  sealing key:      $FSS_KEY_FILE"
            fss_log fail "The journal contents are intact -- the key pair has diverged, and"
            fss_log fail "setup cannot re-converge it, so every boot will fail here until the"
            fss_log fail "FSS state is re-provisioned by hand."
            fss_log fail "Recovery discards sealed history: archive and clear the journal,"
            fss_log fail "remove both keys above, then reboot so setup regenerates the pair."
          else
            fss_log fail "Live active-journal verification failed after FSS activation"
          fi
          printf '%s\n' "$verify_output" | fss_log_block
          write_activation_state failed
          write_live_probe_state unclean
          return 1
        fi

        if [ "$verify_exit" -ne 0 ] \
          && [ -z "$FSS_ARCHIVED_SYSTEM_FAILURES" ] \
          && [ -z "$FSS_USER_FAILURES" ] \
          && [ -z "$FSS_TEMP_FAILURES" ] \
          && [ "$FSS_FILESYSTEM_RESTRICTION" = 0 ]; then
          fss_log fail "journalctl --verify exited $verify_exit after FSS activation without a classified exception"
          printf '%s\n' "$verify_output" | fss_log_block
          write_activation_state failed
          write_live_probe_state unclean
          return 1
        fi

        write_live_probe_state clean
        fss_log info "Confirmed active system journal verifies after FSS activation ($probe_scope probe)"
      }

      activate_journald_for_fss_setup() {
        if journald_activation_already_current; then
          fss_log info "Journald FSS activation is already active for this boot; skipping restart"
          return 0
        fi

        if restart_journald_for_fss_activation; then
          journalctl --sync 2>/dev/null || true
          record_setup_run_pre_activation_archives "$JOURNAL_DIR"
        else
          ACTIVATION_FAILED=1
        fi
      }

      # Re-key transition reconciliation. After recover_from_time_poisoned_sealing
      # discards a poisoned key pair, journals sealed under the old key keep
      # surfacing as failing archives: the generation journald sealed with the
      # old in-memory key between the freeze rotation and the activation
      # restart, and old-lineage actives that only freeze at the next rotation.
      # Decided by key, not timestamp: under the new key an old-lineage archive
      # and a tampered one both report "Tag failed verification", and an mtime
      # window selects FOR archives modified during it, since writing sets mtime.
      receipt_rekey_transition_remainder() {
        local stamp_file="$STATE_DIR/fss-rekey-epoch"
        local stamp grace remaining verify_key sweep_output sweep_path

        [ -f "$stamp_file" ] || return 0
        [ "$ACTIVATION_FAILED" = 0 ] || return 0
        [ -s "$VERIFY_KEY_FILE" ] && [ -r "$VERIFY_KEY_FILE" ] || return 0
        stamp=$(tr -d '[:space:]' < "$stamp_file")
        case "$stamp" in
        "" | *[!0-9]*)
          rm -f "$stamp_file"
          return 0
          ;;
        esac
        # Old-lineage actives freeze only at the next rotation, so a clean sweep
        # does not mean the window is done producing stragglers.
        grace=900

        # Cost bound, not correctness: stop sweeping and let failures stand.
        if [ $(( $(date +%s) - stamp )) -gt 86400 ]; then
          rm -f "$stamp_file"
          fss_log warn "Re-key transaction expired unreconciled; remaining verification failures stand"
          return 0
        fi

        journalctl --rotate 2>/dev/null || true
        journalctl --sync 2>/dev/null || true
        verify_key=$(tr -d '[:space:]' < "$VERIFY_KEY_FILE")
        sweep_output=$(journalctl --verify --verify-key="$verify_key" 2>&1) || true
        remaining=0
        while IFS= read -r sweep_path || [ -n "$sweep_path" ]; do
          [ -n "$sweep_path" ] || continue
          case "$sweep_path" in
          *@*) ;;
          *) continue ;; # never receipt a live journal
          esac
          if archive_verifies_under_retained_key "$sweep_path"; then
            record_recovery_receipt "$sweep_path" "clock-jump-rekey"
          else
            remaining=1
          fi
        done < <(fss_unique_fail_paths_from_output "$sweep_output")

        if [ "$remaining" = 0 ] && [ "$(date +%s)" -gt $(( stamp + grace )) ]; then
          rm -f "$stamp_file"
          fss_log info "Re-key transition reconciled; closing the re-key transaction"
        fi
        # Prune here: this runs from finish_setup, after every other prune site.
        prune_recovery_receipts
      }

      # Exit the setup service, failing closed if sealing activation did not take
      # effect. journald keeps running either way; a non-zero exit makes the
      # unsealed state visible (failed unit + journal-fss-verify alert) instead of
      # silently passing.
      finish_setup() {
        receipt_rekey_transition_remainder
        if [ "$ACTIVATION_FAILED" = 1 ]; then
          fss_log fail "FSS setup finished but sealing activation failed; logs are unsealed"
          exit 1
        fi
        exit 0
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
      # Record any attested backward step first, so the evidence survives into
      # later boots even if this run fails.
      record_clock_jump_attestation
      # Set permissions if possible (may fail in restricted environments like MicroVMs)
      chmod 0755 "/var/log/journal" 2>/dev/null || true
      chmod 2755 "$STATE_DIR" 2>/dev/null || true

      # Snapshot archived system journals present before this setup run touches
      # journald, so record_setup_run_pre_activation_archives can receipt only the
      # archives this run spills out and never a pre-existing (possibly tampered)
      # one.
      SETUP_ARCHIVES_BEFORE=$(mktemp)
      # shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
      cleanup_setup_tmp() {
        rm -f "$SETUP_ARCHIVES_BEFORE"
      }
      trap cleanup_setup_tmp EXIT
      # Broad list: the jump-receipt path gates on membership here, and a
      # time-jump rotation freezes user journals and corpses too.
      list_time_jump_receiptable_journals "$JOURNAL_DIR" > "$SETUP_ARCHIVES_BEFORE" 2>/dev/null || true
      if activation_boundary_recording_needed; then
        RECORD_PRE_ACTIVATION_THIS_RUN=1
      fi

      # Check if FSS keys already exist
      if [ -f "$FSS_KEY_FILE" ]; then
        fss_log info "FSS sealing key already exists at $FSS_KEY_FILE"
        harden_sealing_key "$FSS_KEY_FILE"
        if ! ensure_verification_key_ready; then
          # Keep sentinel so verify service can detect and alert on KEY_MISSING periodically
          fss_log warn "Verification key missing but sealing key present. Verify service will alert."
          publish_setup_state
          if [ "$ACTIVATION_ENABLED" = 1 ]; then
            activate_journald_for_fss_setup
            prune_pre_activation_receipts
            prune_recovery_receipts
            prune_unclean_shutdown_receipts
          fi
          exit 1
        fi
        fss_log info "Setup already complete, verification key present, creating sentinel file"
        publish_setup_state
        if [ "$ACTIVATION_ENABLED" = 1 ] || [ ! -f "$STATE_DIR/fss-rotated" ]; then
          activate_journald_for_fss_setup
        fi
        # One-time rotation to move pre-FSS entries to archive (fixes "Bad message")
        rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE"
        prune_pre_activation_receipts
        prune_recovery_receipts
        prune_unclean_shutdown_receipts
        if ! verify_live_sealing_after_activation; then
          ACTIVATION_FAILED=1
        fi
        finish_setup
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
      harden_sealing_key "$FSS_KEY_FILE"

      if ! ensure_verification_key_ready; then
        # The sealing key exists now, so keep verify enabled to emit KEY_MISSING
        # even when verification key export failed during initial setup.
        fss_log warn "Verification key missing after key generation. Verify service will alert."
        activate_journald_for_fss_setup
        rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE" 1
        prune_pre_activation_receipts
        prune_recovery_receipts
        prune_unclean_shutdown_receipts
        publish_setup_state
        exit 1
      fi

      # Restart journald to pick up the new FSS key
      # Journald only checks for FSS keys at startup, so rotation alone is insufficient
      activate_journald_for_fss_setup

      # Rotate so active journal starts clean with FSS (pre-FSS entries become archive)
      rotate_to_clean_fss_state "$JOURNAL_DIR" "$FSS_KEY_FILE" 1
      prune_pre_activation_receipts
      prune_recovery_receipts
      prune_unclean_shutdown_receipts

      # Create sentinel file to prevent re-initialization
      publish_setup_state
      if ! verify_live_sealing_after_activation; then
        ACTIVATION_FAILED=1
      fi

      fss_log pass "Forward Secure Sealing initialization complete"
      fss_log info "Sealing key: $FSS_KEY_FILE"
      fss_log info "Verification key: $VERIFY_KEY_FILE"
      finish_setup
    '';
  };

  # Script to verify journal integrity
  verifyScript = pkgs.writeShellApplication {
    name = "journal-fss-verify";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
      util-linux
      gnugrep
      gawk
    ];
    # /etc/fss-verify-classifier.sh is populated at runtime (see environment.etc
    # above); shellcheck cannot follow it statically.
    excludeShellChecks = [ "SC1091" ];
    text = ''
            source /etc/fss-verify-classifier.sh

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
            RECOVERY_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-recovery-receipts"
            PRE_ACTIVATION_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-pre-activation-receipts"
            UNCLEAN_SHUTDOWN_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-unclean-shutdown-receipts"
            ACTIVATION_STATE_FILE="/var/log/journal/$MACHINE_ID/fss-activation-state"
            FSS_BOOT_BASELINE_FILE="/var/log/journal/$MACHINE_ID/fss-baseline-boot"
            CURRENT_BOOT_ID=$(fss_current_boot_id)
            ACTIVATION_ENABLED="${if activationEnabled then "1" else "0"}"
            VERIFY_KEY=$(tr -d '[:space:]' < "$VERIFY_KEY_FILE")

            if [ "$ACTIVATION_ENABLED" = 1 ]; then
              ACTIVATION_STATE=""
              ACTIVATION_BOOT_ID=""
              ACTIVATION_BASELINE_BOOT_ID=""
              if [ -r "$ACTIVATION_STATE_FILE" ]; then
                ACTIVATION_STATE=$(awk -F '\t' 'NR == 1 { print $1 }' "$ACTIVATION_STATE_FILE")
                ACTIVATION_BOOT_ID=$(awk -F '\t' 'NR == 1 { print $2 }' "$ACTIVATION_STATE_FILE")
              fi
              if [ -r "$FSS_BOOT_BASELINE_FILE" ]; then
                ACTIVATION_BASELINE_BOOT_ID=$(tr -d '[:space:]' < "$FSS_BOOT_BASELINE_FILE")
              fi

              if [ "$ACTIVATION_STATE" = "failed" ]; then
                audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: FSS activation failed; journald sealing not confirmed [ACTIVATION_FAILED]"
                fss_log fail "Journal integrity verification: FAILED (FSS sealing was not activated; logs are unsealed)"
                exit 1
              fi

              if [ "$ACTIVATION_STATE" != "active" ] \
                || [ "$ACTIVATION_BOOT_ID" != "$CURRENT_BOOT_ID" ] \
                || [ "$ACTIVATION_BASELINE_BOOT_ID" != "$CURRENT_BOOT_ID" ]; then
                audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: FSS activation is not active for the current boot [ACTIVATION_STALE]"
                fss_log fail "Journal integrity verification: FAILED (FSS activation state is not active for current boot; state=''${ACTIVATION_STATE:-missing} boot=''${ACTIVATION_BOOT_ID:-missing} baseline=''${ACTIVATION_BASELINE_BOOT_ID:-missing})"
                exit 1
              fi

              if ! fss_sealing_active_in_config; then
                audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: FSS activation failed; effective journald Seal setting is not yes [ACTIVATION_FAILED]"
                fss_log fail "Journal integrity verification: FAILED (effective journald Seal setting is not yes)"
                exit 1
              fi
            fi

            # journalctl walks the live journal while journald is still
            # appending to it, so the object counts it accumulates can
            # disagree with the header counters by the time it compares them.
            # That surfaces as an active-system failure on a perfectly healthy
            # machine -- observed on a freshly flashed device one second after
            # setup's own probe passed the same file.
            #
            # --sync alone does not close it: the append continues for the
            # duration of the walk. So re-verify, and only for that signature:
            # anything that indicts the content (tag, hash, epoch) is believed
            # on the first attempt, and a counter mismatch that survives every
            # attempt is reported as a failure exactly as before.
            attempt=1
            while :; do
              journalctl --sync 2>/dev/null || true
              VERIFY_EXIT=0
              VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?
              fss_classify_verify_output "$VERIFY_OUTPUT"

              if ! fss_active_failure_retryable "$VERIFY_OUTPUT" "$FSS_ACTIVE_SYSTEM_FAILURES"; then
                break
              fi
              if [ "$attempt" -ge "${toString cfg.verifyRetries}" ]; then
                fss_log warn "Active-journal counter mismatch persisted across ${toString cfg.verifyRetries} verifies; reporting it"
                break
              fi
              fss_log info "Active-journal counter mismatch on attempt $attempt; journald was appending during the walk, re-verifying"
              attempt=$((attempt + 1))
              sleep 2
            done

            # Content-bind lifecycle receipts to disk. Missing archives may be
            # journald retention, but an existing path with different content is
            # substitution/path reuse and fails even if journalctl is clean.
            RAW_RECOVERY_RECEIPTS=$(fss_read_receipts "$RECOVERY_RECEIPTS_FILE")
            RECOVERY_RECEIPT_MISMATCHES=$(fss_receipt_mismatches "$RAW_RECOVERY_RECEIPTS")
            if [ -n "$RECOVERY_RECEIPT_MISMATCHES" ]; then
              audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: Recovery receipt content mismatch [RECOVERY_RECEIPT_MISMATCH]"
              fss_log fail "Journal integrity verification: FAILED (recovery receipt content mismatch)"
              printf 'Mismatched receipt paths:\n%s\n' "$RECOVERY_RECEIPT_MISMATCHES" | fss_log_block
              exit 1
            fi
            RECOVERY_RECEIPTS=$(fss_filter_valid_receipts "$RAW_RECOVERY_RECEIPTS")

            RAW_PRE_ACTIVATION_RECEIPTS=$(fss_read_pre_activation_receipts "$PRE_ACTIVATION_RECEIPTS_FILE")
            PRE_ACTIVATION_RECEIPT_MISMATCHES=$(fss_pre_activation_receipt_mismatches "$RAW_PRE_ACTIVATION_RECEIPTS")
            if [ -n "$PRE_ACTIVATION_RECEIPT_MISMATCHES" ]; then
              audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: Pre-activation receipt content mismatch [PRE_ACTIVATION_RECEIPT_MISMATCH]"
              fss_log fail "Journal integrity verification: FAILED (pre-activation receipt content mismatch)"
              printf 'Mismatched receipt paths:\n%s\n' "$PRE_ACTIVATION_RECEIPT_MISMATCHES" | fss_log_block
              exit 1
            fi
            PRE_ACTIVATION_RECEIPTS=$(fss_filter_valid_receipts "$RAW_PRE_ACTIVATION_RECEIPTS")

            RAW_UNCLEAN_RECEIPTS=$(fss_read_unclean_shutdown_receipts "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE")
            UNCLEAN_RECEIPT_MISMATCHES=$(fss_unclean_shutdown_receipt_mismatches "$RAW_UNCLEAN_RECEIPTS")
            if [ -n "$UNCLEAN_RECEIPT_MISMATCHES" ]; then
              audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: Unclean-shutdown receipt content mismatch [UNCLEAN_SHUTDOWN_RECEIPT_MISMATCH]"
              fss_log fail "Journal integrity verification: FAILED (unclean-shutdown receipt content mismatch)"
              printf 'Mismatched receipt paths:\n%s\n' "$UNCLEAN_RECEIPT_MISMATCHES" | fss_log_block
              exit 1
            fi
            UNCLEAN_RECEIPTS=$(fss_filter_valid_receipts "$RAW_UNCLEAN_RECEIPTS")

            fss_classify_verify_output "$VERIFY_OUTPUT"
            fss_verify_policy_decision \
              "$(fss_read_recorded_pre_fss_archive "$PRE_FSS_ARCHIVE_FILE")" \
              "$RECOVERY_RECEIPTS" \
              "$PRE_ACTIVATION_RECEIPTS" \
              "$CURRENT_BOOT_ID" \
              "$VERIFY_EXIT" \
              "$UNCLEAN_RECEIPTS"

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
            warning)
              audit_log warning "WARNING: Journal integrity verification raised warnings [$FSS_VERDICT_TAGS]"
              fss_log warn "Journal integrity verification: WARNING ($FSS_VERDICT_REASON)"
              fss_log_block <<EOF
      Output: $VERIFY_OUTPUT
      EOF
              exit 0
              ;;
            verified)
              audit_log info "AUDIT_LOG_VERIFY_COMPLETED: Journal integrity verification passed"
              fss_log pass "Journal integrity verification: VERIFIED"
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

        VM components must also enable ghaf.storagevm.enable so /var/log/journal
        and the journald sealing key are persisted. Set this option explicitly
        to false only for intentionally stateless logged VMs.

        FSS provides cryptographic tamper-evidence for audit logs
        using HMAC-based sealing chains. Any tampering will break
        the chain and be detected during verification.
      '';
    };

    activation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable an explicit per-boot FSS activation boundary.

          When enabled, journald is explicitly configured with Seal=no during
          early boot. The FSS setup service writes a runtime journald drop-in,
          restarts journald, and rotates logs after clock readiness so entries
          before that point are treated as collected but not FSS-trusted.

          Entries written before activation land in archives that are recorded as
          content-bound lifecycle receipts (see activation.maxReceipts) and
          surface as "warning" during verification, whether the matching
          receipt is from the current boot or an earlier one; a content
          mismatch fails closed.

          Security note: enabling this trades a per-boot window of unsealed logs
          (between journald start and activation) for resilience against the
          journald wall-clock-jump corruption. Disabling it restores static
          Seal=yes from early boot. This defaults to true, so upgrading an
          existing FSS deployment moves it from sealed-from-boot to
          activate-after-clock-ready; sealing then depends on the setup service
          completing each boot, and the verifier fails closed if it cannot
          confirm sealing took effect.
        '';
      };

      syncWaitSeconds = mkOption {
        type = types.int;
        default = 120;
        description = ''
          Maximum number of seconds to wait for system time synchronization
          (reported by the configured time daemon) after local clock readiness before
          activating FSS sealing.

          This is a best-effort soft gate, not a hard requirement: on an offline
          device NTP never synchronises, so activation proceeds anyway once this
          timeout elapses, sealing on the local (possibly unsynchronised) clock.
          Clock readiness is a boot gate and mitigation, not a trusted time
          source.
        '';
      };

      maxReceipts = mkOption {
        type = types.int;
        default = 64;
        description = ''
          Upper bound on retained pre-activation lifecycle receipts.

          The setup service caps the receipt store at this many records, evicting
          the oldest with a warning when exceeded. Receipts are matched against
          on-disk archives by content (sha256) at verify time, so a receipt for a
          deleted archive is harmless; this cap is the growth backstop against
          frequent reboots.
        '';
      };
    };

    uncleanShutdown = {
      maxReceipts = mkOption {
        type = types.int;
        default = 64;
        description = ''
          Upper bound on retained unclean-shutdown lifecycle receipts.

          The setup service records a content-bound receipt for each journal that
          journald itself reported as uncleanly shut down (host crash, power loss,
          stop-timeout SIGKILL), and caps the store at this many records. Receipts
          are matched by sha256 at verify time, so a receipt for a deleted archive
          is harmless; this is the growth backstop against repeated unclean kills.
        '';
      };
    };

    staticSealEnabled = mkOption {
      type = types.bool;
      internal = true;
      readOnly = true;
      default = cfg.enable && !cfg.activation.enable;
      description = ''
        Whether journald is statically sealed (Seal=yes) from early boot.

        Single source of truth shared by the host, client, and server journald
        configs so the static-seal condition cannot drift between them. False
        when the per-boot activation boundary (activation.enable) is in effect,
        because sealing is then activated at runtime by the FSS setup service.
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

    rekey = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether setup may recover automatically from a sealing epoch left
          ahead of the wall clock by a backward realtime step.

          journald cannot walk an FSPRG epoch backwards, and stops writing tags
          entirely while its epoch is ahead of realtime, so without recovery
          the machine fails verification on every boot for the length of the
          step. Recovery is nonetheless destructive: it discards the key pair
          and re-keys, after which journals sealed before the jump no longer
          verify under the live key. It runs only when journald itself attested
          the step. Set this to false for a deployment that would rather fail
          closed and have a human decide.
        '';
      };

      attestationValiditySeconds = mkOption {
        type = types.int;
        default = 604800;
        description = ''
          How long journald's attestation of a backward clock step authorises
          an automatic re-key.

          Time-based expiry is admittedly the wrong shape: a poisoned sealing
          epoch persists for the magnitude of the step, which can outlast any
          window. But a stamp that never expires is a standing authorisation to
          destroy keys, which is worse. Past the window an operator
          re-provisions by hand, which is the correct fail-closed default.
        '';
      };

      maxAttempts = mkOption {
        type = types.int;
        default = 3;
        description = ''
          Automatic re-keys permitted within attemptWindowSeconds.

          The in-process guard only bounds a single setup invocation chain, and
          ghaf-clock-jump-watcher restarts setup on every new attestation, so
          this is what stops a condition that survives a re-key from destroying
          the key pair again on every trigger.
        '';
      };

      attemptWindowSeconds = mkOption {
        type = types.int;
        default = 86400;
        description = "Window over which rekey.maxAttempts is counted.";
      };

      retainedKeys = mkOption {
        type = types.int;
        default = 2;
        description = ''
          How many superseded verification keys to keep alongside the live one.

          A re-key regenerates the seed and start_usec, so journals sealed
          before it can never be verified with the new key. Retaining the
          outgoing key keeps that history auditable offline, and lets the
          transition sweep prove an archive belongs to a pre-re-key lineage
          cryptographically instead of inferring it from timestamps.

          The cost is exposure: an FSS verification key is seed + start +
          interval, so possession allows forging entries from that epoch
          forward, not merely verifying them. Retained keys are 0400 root
          inside the 0700 key directory. On a guest that directory is a
          virtiofs share from the host, so retained guest keys are readable to
          whatever on the host can read the share -- the same class of exposure
          as the live key, but N times more of it. Set to 0 to keep none,
          accepting that pre-jump history becomes permanently unverifiable and
          that the sweep loses its discriminator.
        '';
      };
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

        Do not lower this without measuring. A FORWARD clock step -- which is
        what an RTC-less board does on every boot once NTP answers -- costs
        journald one 1536-bit modular squaring and one 64-byte tag object per
        missed interval, walked synchronously on the log-append path with no
        cap (journal_file_fsprg_evolve; the epoch cannot be sought forward
        because journald holds no seed). The cost is linear in 1/sealInterval:
        at the 15min default a multi-month step is some thousands of
        evolutions and unnoticeable, at "10s" the same step is over a million,
        which is tens of seconds of blocked journald and enough tag objects to
        drive rotation and vacuuming of real log data.

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

    verifyRetries = mkOption {
      type = types.ints.positive;
      default = 3;
      description = ''
        How many times to verify before believing an active-journal counter
        mismatch.

        journalctl walks the live journal while journald appends to it, so the
        object counts it accumulates can disagree with the header counters it
        compares them against -- a failure on a healthy machine, and one that
        --sync cannot prevent because the append continues for the duration of
        the walk. Only that signature is retried; anything indicting the
        content is believed on the first attempt, and a mismatch surviving
        every attempt is still reported as a failure.

        Set to 1 to disable retrying.
      '';
    };
  };

  config = mkMerge [

    # Single on-disk copy of the verification/receipt classifier, sourced at
    # runtime by journal-fss-setup, journal-fss-verify, fss-triage, fss-test,
    # and common.nix's clock-jump recovery -- unconditional (not gated by
    # cfg.enable) since that last consumer runs even when FSS itself is off.
    { environment.etc."fss-verify-classifier.sh".source = ./fss-verify-classifier.sh; }

    (mkIf cfg.enable {
      assertions = [
        {
          assertion = hasPersistentJournalStorage;
          message = "FSS on VMs requires ghaf.storagevm.enable so /var/log/journal and the journald sealing key are persisted.";
        }
      ];

      # Enable audit subsystem for FSS monitoring
      # This provides auditctl and enables the audit rules defined below
      # FSS requires audit to be enabled, so we use mkForce to ensure it's on
      # regardless of profile settings (audit is fundamental to FSS functionality)
      ghaf.security.audit.enable = lib.mkForce true;

      environment.systemPackages = [
        fssTriagePackage
      ];

      # FSS is only meaningful for persistent journals. The journald sealing key
      # lives beside the journal files and is advanced by journald over time.
      services.journald =
        if hasStructuredJournald then
          {
            settings.Journal = {
              Storage = "persistent";
              Seal = cfg.staticSealEnabled;
            };
          }
        else
          {
            extraConfig = lib.mkAfter ''
              Storage=persistent
              Seal=${if cfg.staticSealEnabled then "yes" else "no"}
            '';
          };

      ghaf.storagevm.preserveLogs = mkIf (config.ghaf.type != "host") true;

      # Create key directory and journal directory via tmpfiles
      # Note: In VMs, ${cfg.keyPath} is a virtiofs mount point, so we only create it on host
      systemd = {
        tmpfiles.rules =
          lib.optionals (config.ghaf.type == "host") [
            "d /persist/common/journal-fss 0755 root root - -"
            "d ${cfg.keyPath} 0700 root root - -"
            "d /persist/var 0755 root root - -"
            "d /persist/var/log 0755 root root - -"
            "d ${hostPersistentJournalPath} 2755 root systemd-journal - -"
          ]
          ++ [
            "d /var/log/journal 2755 root systemd-journal - -"
          ];

        mounts = lib.optionals (config.ghaf.type == "host") [
          {
            what = hostPersistentJournalPath;
            where = "/var/log/journal";
            type = "none";
            options = "bind";
            wantedBy = [ "local-fs.target" ];
            requiredBy = [ "journal-fss-setup.service" ];
            requires = [ "journal-fss-prepare-persistent-journal.service" ];
            after = [
              "journal-fss-prepare-persistent-journal.service"
              "persist.mount"
            ];
            before = [
              "systemd-journal-flush.service"
              "journal-fss-setup.service"
            ];
            unitConfig.DefaultDependencies = false;
          }
        ];

        services = {
          journal-fss-prepare-persistent-journal = mkIf (config.ghaf.type == "host") {
            description = "Prepare persistent journal storage for FSS";

            after = [
              "local-fs-pre.target"
              "persist.mount"
            ];
            before = [
              "var-log-journal.mount"
              "systemd-journal-flush.service"
              "journal-fss-setup.service"
            ];

            unitConfig = {
              DefaultDependencies = false;
              RequiresMountsFor = [ "/persist" ];
            };

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = getExe preparePersistentJournalScript;
            };
          };

          # One-shot service to generate FSS keys on first boot
          # Runs after journald is ready, then restarts journald to enable sealing
          journal-fss-setup = {
            description = "Setup Forward Secure Sealing keys for systemd journal";
            documentation = [ "man:journalctl(1)" ];

            wantedBy = [ "multi-user.target" ];
            after = [
              "systemd-journald.service"
              "systemd-journal-flush.service"
            ]
            ++ lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
              # Wait for the time-sync barrier (after networking) before activating
              # sealing, without making the early journal flush wait on it.
              "ghaf-clock-sync.service"
            ]
            ++ lib.optionals (config.ghaf.type == "host") [
              "var-log-journal.mount"
            ];
            wants = [
              "systemd-journald.service"
              "systemd-journal-flush.service"
            ]
            ++ lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
              "ghaf-clock-sync.service"
            ];
            requires = lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
            ];

            unitConfig = {
              RequiresMountsFor = [
                cfg.keyPath
                "/var/log/journal"
              ];
              StartLimitIntervalSec = "0";
            };

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = getExe setupScript;
            };
          };

          # Service to verify journal integrity
          journal-fss-verify = {
            description = "Verify systemd journal integrity using Forward Secure Sealing";
            documentation = [ "man:journalctl(1)" ];

            after = [
              "systemd-journald.service"
              "journal-fss-setup.service"
            ]
            ++ lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
            ];
            wants = [
              "systemd-journald.service"
              "journal-fss-setup.service"
            ]
            ++ lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
            ];
            requires = lib.optionals clockReadyEnabled [
              "ghaf-clock-ready.service"
            ];

            unitConfig = {
              # Only run if FSS setup has completed successfully
              ConditionPathExists = "${cfg.keyPath}/initialized";
              StartLimitIntervalSec = "0";
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
    })
  ];
}
