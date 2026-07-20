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
#   FSS-trusted. They are recorded as content-bound lifecycle receipts and pass
#   verification as "verified-with-exception" only for the current boot; a
#   pre-activation archive failing verification for an earlier boot is a warning,
#   while one whose content no longer matches its receipt fails closed.
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
  clockReadyEnabled =
    cfg.enable && config.ghaf.logging.recovery.enable && config.ghaf.logging.recovery.clockReady.enable;
  activationEnabled = cfg.activation.enable;
  loggingEnabled = config.ghaf.logging.enable;
  hasPersistentJournalStorage = config.ghaf.type == "host" || config.ghaf.storagevm.enable;
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
      ACTIVATION_ENABLED="${if activationEnabled then "1" else "0"}"
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

      record_lifecycle_receipt() {
        local receipt_file="$1"
        local archive_path="$2"
        local reason="$3"
        local log_level="$4"
        local log_message="$5"
        local inode size mtime sha boot event

        [ -n "$archive_path" ] && [ -f "$archive_path" ] || return 0

        inode=$(stat -c %i "$archive_path" 2>/dev/null || true)
        size=$(stat -c %s "$archive_path" 2>/dev/null || true)
        mtime=$(stat -c %Y "$archive_path" 2>/dev/null || true)
        sha=$(sha256sum "$archive_path" 2>/dev/null | cut -d' ' -f1 || true)
        boot=$(current_boot_id)
        event="''${INVOCATION_ID:-$boot}"

        if [ -z "$inode" ] || [ -z "$size" ] || [ -z "$mtime" ] || ! fss_valid_sha256 "$sha"; then
          fss_log warn "Could not record lifecycle receipt for $archive_path: missing stat or sha256 evidence"
          return 0
        fi

        # Dedupe on the physical archive identity (path + inode + size).
        if [ -f "$receipt_file" ] \
          && awk -F '\t' -v p="$archive_path" -v i="$inode" -v s="$size" \
            '$2 == p && $3 == i && $4 == s { found = 1 } END { exit found ? 0 : 1 }' \
            "$receipt_file"; then
          return 0
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$FSS_RECEIPT_SCHEMA_VERSION" "$archive_path" "$inode" "$size" \
          "$boot" "$mtime" "$sha" "$reason" "$event" \
          >> "$receipt_file"
        chmod 0644 "$receipt_file"
        fss_log "$log_level" "$log_message: $archive_path"
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

        record_lifecycle_receipt \
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
        record_lifecycle_receipt \
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
      # The verifier treats a content-matched unclean receipt as
      # verified-with-exception; an unmatched .journal~ or the live system.journal
      # still fails closed. See fss-verify-classifier.sh policy.
      record_unclean_shutdown_receipt() {
        local archive_path="$1"
        record_lifecycle_receipt \
          "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" \
          "$archive_path" \
          "unclean-shutdown" \
          warn \
          "Recorded unclean-shutdown journal receipt"
      }

      # Journal paths journald named as uncleanly shut down in the current boot.
      unclean_shutdown_named_paths() {
        journalctl -b -u systemd-journald.service \
          --grep="corrupted or uncleanly shut down, renaming and replacing" \
          --output=cat --quiet --no-pager 2>/dev/null \
          | grep -oE '/var/log/journal/[^ ]+\.journal' \
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

      # Bound the receipt store by capping to the newest PRE_ACTIVATION_MAX_RECEIPTS
      # records (the file is append-ordered oldest-first). Receipts are NOT dropped
      # merely because an archive is currently absent: a receipt for a vanished
      # archive is harmless (the verifier's fss_filter_valid_receipts ignores it,
      # and a deleted archive never appears as a verify failure), and dropping on
      # transient absence would lose coverage for an archive that returns. The cap
      # is the growth backstop; content substitution is caught at verify time.
      prune_pre_activation_receipts() {
        local tmp total excess

        [ -f "$PRE_ACTIVATION_RECEIPTS_FILE" ] || return 0

        total=$(wc -l < "$PRE_ACTIVATION_RECEIPTS_FILE" 2>/dev/null || echo 0)
        [ "$total" -gt "$PRE_ACTIVATION_MAX_RECEIPTS" ] || return 0

        excess=$((total - PRE_ACTIVATION_MAX_RECEIPTS))
        tmp=$(mktemp)
        tail -n "$PRE_ACTIVATION_MAX_RECEIPTS" "$PRE_ACTIVATION_RECEIPTS_FILE" > "$tmp"
        mv "$tmp" "$PRE_ACTIVATION_RECEIPTS_FILE"
        chmod 0644 "$PRE_ACTIVATION_RECEIPTS_FILE"
        fss_log warn "Pre-activation receipts exceeded $PRE_ACTIVATION_MAX_RECEIPTS; evicted $excess oldest record(s)"
      }

      prune_recovery_receipts() {
        local tmp total excess

        [ -f "$RECOVERY_RECEIPTS_FILE" ] || return 0

        total=$(wc -l < "$RECOVERY_RECEIPTS_FILE" 2>/dev/null || echo 0)
        [ "$total" -gt "$RECOVERY_MAX_RECEIPTS" ] || return 0

        excess=$((total - RECOVERY_MAX_RECEIPTS))
        tmp=$(mktemp)
        tail -n "$RECOVERY_MAX_RECEIPTS" "$RECOVERY_RECEIPTS_FILE" > "$tmp"
        mv "$tmp" "$RECOVERY_RECEIPTS_FILE"
        chmod 0644 "$RECOVERY_RECEIPTS_FILE"
        fss_log warn "Recovery receipts exceeded $RECOVERY_MAX_RECEIPTS; evicted $excess oldest record(s)"
      }

      prune_unclean_shutdown_receipts() {
        local tmp total excess

        [ -f "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" ] || return 0

        total=$(wc -l < "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" 2>/dev/null || echo 0)
        [ "$total" -gt "$UNCLEAN_SHUTDOWN_MAX_RECEIPTS" ] || return 0

        excess=$((total - UNCLEAN_SHUTDOWN_MAX_RECEIPTS))
        tmp=$(mktemp)
        tail -n "$UNCLEAN_SHUTDOWN_MAX_RECEIPTS" "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE" > "$tmp"
        mv "$tmp" "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE"
        chmod 0644 "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE"
        fss_log warn "Unclean-shutdown receipts exceeded $UNCLEAN_SHUTDOWN_MAX_RECEIPTS; evicted $excess oldest record(s)"
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

      current_boot_id() {
        cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot
      }

      boot_start_epoch() {
        awk -v now="$(date +%s)" '{printf "%d\n", now - $1}' /proc/uptime
      }

      write_boot_baseline_record() {
        printf '%s\n' "$(current_boot_id)" > "$FSS_BOOT_BASELINE_FILE"
        chmod 0644 "$FSS_BOOT_BASELINE_FILE"
      }

      boot_baseline_current() {
        [ -s "$FSS_BOOT_BASELINE_FILE" ] || return 1
        [ "$(tr -d '[:space:]' < "$FSS_BOOT_BASELINE_FILE")" = "$(current_boot_id)" ]
      }

      current_boot_time_jump_epochs() {
        {
          journalctl -b -u systemd-journald.service \
            --grep="Time jumped backwards, rotating" \
            --output=short-unix \
            --quiet \
            --no-pager 2>/dev/null || true
          journalctl -b -u systemd-journald.service \
            --grep="Realtime clock jumped backwards relative to last journal entry, rotating" \
            --output=short-unix \
            --quiet \
            --no-pager 2>/dev/null || true
        } | awk '
          $1 ~ /^[0-9]+([.][0-9]+)?$/ {
            split($1, ts, ".")
            print ts[1]
          }
        ' | sort -u
      }

      archive_mtime_matches_time_jump_epoch() {
        local archive_mtime="$1"
        local time_jump_epochs="$2"
        local event_epoch=""
        local window_sec=10
        local lower=0
        local upper=0

        while IFS= read -r event_epoch || [ -n "$event_epoch" ]; do
          case "$event_epoch" in
          "" | *[!0-9]*) continue ;;
          esac

          lower=$((event_epoch - window_sec))
          upper=$((event_epoch + window_sec))
          if [ "$archive_mtime" -ge "$lower" ] && [ "$archive_mtime" -le "$upper" ]; then
            return 0
          fi
        done <<< "$time_jump_epochs"

        return 1
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
            && archive_mtime_matches_time_jump_epoch "$archive_mtime" "$time_jump_epochs"; then
            if [ "$ACTIVATION_ENABLED" = 1 ]; then
              record_pre_activation_receipt "$archive_path" "pre-activation-time-jump"
            else
              record_recovery_receipt "$archive_path" "clock-jump-recovery"
            fi
          fi
        done < <(list_archived_system_journals "$journal_dir")
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
        printf '%s\t%s\n' "$1" "$(current_boot_id)" > "$ACTIVATION_STATE_FILE"
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
          && [ "$(activation_state_boot_id)" = "$(current_boot_id)" ]
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
          && sealing_active_in_config
      }

      sealing_active_in_config() {
        local effective_seal

        effective_seal=$(
          systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
            | awk -F= '
              /^[[:space:]]*[#;]/ { next }
              /^[[:space:]]*Seal[[:space:]]*=/ {
                value = $2
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*[#;].*$/, "", value)
                sub(/[[:space:]]*$/, "", value)
                seal = tolower(value)
              }
              END { print seal }
            '
        )
        [ "$effective_seal" = "yes" ]
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

        if [ "$restart_ok" = 1 ] && sealing_active_in_config; then
          ACTIVATION_RESTARTED_THIS_RUN=1
          write_activation_state active
          fss_log info "Confirmed journald sealing is active after restart"
          return 0
        fi

        fss_log fail "Journald sealing could not be confirmed after restart; failing closed"
        write_activation_state failed
        return 1
      }

      verify_live_sealing_after_activation() {
        local verify_key verify_output verify_exit marker

        [ "$ACTIVATION_ENABLED" = 1 ] || return 0
        [ "$ACTIVATION_RESTARTED_THIS_RUN" = 1 ] || return 0
        [ "$ACTIVATION_FAILED" = 0 ] || return 1
        [ -s "$VERIFY_KEY_FILE" ] && [ -r "$VERIFY_KEY_FILE" ] || return 0

        marker="FSS activation live sealing probe $(current_boot_id) $$"
        logger -t journal-fss "$marker" 2>/dev/null || true
        journalctl --sync 2>/dev/null || true

        verify_key=$(tr -d '[:space:]' < "$VERIFY_KEY_FILE")
        verify_exit=0
        verify_output=$(journalctl --verify --verify-key="$verify_key" 2>&1) || verify_exit=$?
        fss_classify_verify_output "$verify_output"

        if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] \
          || [ -n "$FSS_OTHER_FAILURES" ] \
          || [ "$FSS_KEY_PARSE_ERROR" = 1 ] \
          || [ "$FSS_KEY_REQUIRED_ERROR" = 1 ]; then
          fss_log fail "Live active-journal verification failed after FSS activation"
          printf '%s\n' "$verify_output" | fss_log_block
          write_activation_state failed
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
          return 1
        fi

        fss_log info "Confirmed active system journal verifies after FSS activation"
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

      # Exit the setup service, failing closed if sealing activation did not take
      # effect. journald keeps running either way; a non-zero exit makes the
      # unsealed state visible (failed unit + journal-fss-verify alert) instead of
      # silently passing.
      finish_setup() {
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
      list_archived_system_journals "$JOURNAL_DIR" > "$SETUP_ARCHIVES_BEFORE" 2>/dev/null || true
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

            journald_effective_seal() {
              systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
                | awk -F= '
                  /^[[:space:]]*[#;]/ { next }
                  /^[[:space:]]*Seal[[:space:]]*=/ {
                    value = $2
                    sub(/^[[:space:]]*/, "", value)
                    sub(/[[:space:]]*[#;].*$/, "", value)
                    sub(/[[:space:]]*$/, "", value)
                    seal = tolower(value)
                  }
                  END { print seal }
                '
            }

            sealing_active_in_config() {
              [ "$(journald_effective_seal)" = "yes" ]
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
            CURRENT_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot)
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

              if ! sealing_active_in_config; then
                audit_log crit "AUDIT_LOG_INTEGRITY_FAIL: FSS activation failed; effective journald Seal setting is not yes [ACTIVATION_FAILED]"
                fss_log fail "Journal integrity verification: FAILED (effective journald Seal setting is not yes)"
                exit 1
              fi
            fi

            VERIFY_EXIT=0
            VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?

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
            verified-with-exception)
              audit_log notice "AUDIT_LOG_VERIFY_COMPLETED: Journal integrity verified with recorded exception [$FSS_VERDICT_TAGS]"
              fss_log pass "Journal integrity verification: VERIFIED WITH EXCEPTION ($FSS_VERDICT_REASON)"
              if [ "$VERIFY_EXIT" -ne 0 ]; then
                fss_log info "Note: journalctl --verify returned exit $VERIFY_EXIT without critical errors [$FSS_VERDICT_TAGS]"
              fi
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
          content-bound lifecycle receipts (see activation.maxReceipts) and pass
          verification as "verified-with-exception" for the current boot. An
          earlier-boot receipt is downgraded to "warning"; a content mismatch
          fails closed.

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
          (timedatectl NTPSynchronized) after local clock readiness before
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

    # Single on-disk copy of the verification/receipt classifier, sourced at
    # runtime by journal-fss-setup, journal-fss-verify, fss-triage, and
    # fss-test instead of each embedding its own build-time inlined copy.
    environment.etc."fss-verify-classifier.sh".source = ./fss-verify-classifier.sh;

    # FSS is only meaningful for persistent journals. The journald sealing key
    # lives beside the journal files and is advanced by journald over time.
    services.journald.extraConfig = lib.mkAfter ''
      Storage=persistent
      Seal=${if cfg.staticSealEnabled then "yes" else "no"}
    '';

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
  };
}
