# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Manual FSS triage script.
#
# This is intentionally separate from fss-test. It collects diagnostics and
# runs targeted verification probes for investigating intermittent FSS/journald
# failures on deployed systems.
{
  writeShellApplication,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  systemd,
  util-linux,
}:
let
  verifyClassifierLib = builtins.readFile ../../../modules/common/logging/fss-verify-classifier.sh;
in
writeShellApplication {
  name = "fss-triage";
  runtimeInputs = [
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    systemd
    util-linux
  ];
  text = ''
    ${verifyClassifierLib}

    usage() {
      cat <<'EOF'
    Usage: fss-triage [options]

    Collect FSS/journald diagnostics and run manual verification probes.

    Options:
      --output-dir DIR          Write diagnostics under DIR.
      --no-sync                 Do not run journalctl --sync before the main verify pass.
      --recovery-probe          Start ghaf-journal-alloy-recover.service after baseline capture and verify again.
      --journald-restart-probe  Restart systemd-journald.service twice after baseline capture and verify again.
      --strict-exit             Exit non-zero when a critical verification verdict is observed.
      -h, --help                Show this help.

    Default behavior is evidence-preserving: no service restarts are performed.
    EOF
    }

    OUTPUT_DIR=""
    DO_SYNC=1
    DO_RECOVERY_PROBE=0
    DO_JOURNALD_RESTART_PROBE=0
    STRICT_EXIT=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
      --output-dir)
        [ "$#" -ge 2 ] || { echo "--output-dir requires a value" >&2; exit 2; }
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --no-sync)
        DO_SYNC=0
        shift
        ;;
      --recovery-probe)
        DO_RECOVERY_PROBE=1
        shift
        ;;
      --journald-restart-probe)
        DO_JOURNALD_RESTART_PROBE=1
        shift
        ;;
      --strict-exit)
        STRICT_EXIT=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
      esac
    done

    HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown-host)"
    TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    umask 077
    if [ -z "$OUTPUT_DIR" ]; then
      SAFE_HOSTNAME="$(printf '%s' "$HOSTNAME" | tr -c 'A-Za-z0-9_.-' '_')"
      OUTPUT_DIR="$(mktemp -d "''${TMPDIR:-/tmp}/fss-triage-$SAFE_HOSTNAME-$TIMESTAMP-XXXXXX")"
    fi
    mkdir -p "$OUTPUT_DIR"/verify "$OUTPUT_DIR"/units

    COMMAND_LOG="$OUTPUT_DIR/commands.tsv"
    SUMMARY="$OUTPUT_DIR/summary.txt"
    VERIFY_SUMMARY="$OUTPUT_DIR/verify/summary.tsv"
    RECEIPT_SUMMARY="$OUTPUT_DIR/receipt-summary.tsv"
    CRITICAL_FAILURE=0

    printf 'name\texit_code\tcommand\n' > "$COMMAND_LOG"
    printf 'name\texit_code\tverdict\ttags\treason\n' > "$VERIFY_SUMMARY"
    printf 'class\ttotal\tvalid\tcurrent\tstale\tmissing\tmismatched\n' > "$RECEIPT_SUMMARY"

    info() { fss_log info "$1"; }
    warn() { fss_log warn "$1"; }
    pass() { fss_log pass "$1"; }

    append_command_log() {
      local name="$1"
      local rc="$2"
      local arg
      local redact_next=0
      shift 2

      {
        printf '%s\t%s\t' "$name" "$rc"
        for arg in "$@"; do
          if [ "$redact_next" -eq 1 ]; then
            printf '%q ' "<redacted>"
            redact_next=0
            continue
          fi

          case "$arg" in
          --verify-key=*) printf '%q ' "--verify-key=<redacted>" ;;
          --verify-key)
            printf '%q ' "$arg"
            redact_next=1
            ;;
          *) printf '%q ' "$arg" ;;
          esac
        done
        printf '\n'
      } >> "$COMMAND_LOG"
    }

    run_capture() {
      local name="$1"
      shift
      local output="$OUTPUT_DIR/$name.txt"
      local rc

      set +e
      {
        printf '$'
        printf ' %q' "$@"
        printf '\n\n'
        "$@"
      } >"$output" 2>&1
      rc=$?
      set -e

      append_command_log "$name" "$rc" "$@"
      return 0
    }

    run_shell_capture() {
      local name="$1"
      local script="$2"
      run_capture "$name" "$BASH" -lc "$script"
    }

    read_file_if_present() {
      local path="$1"
      if [ -r "$path" ]; then
        cat "$path"
      fi
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

    journald_config_has_seal_no() {
      systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
        | awk -F= '
          /^[[:space:]]*[#;]/ { next }
          /^[[:space:]]*Seal[[:space:]]*=/ {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*[#;].*$/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (tolower(value) == "no") found = 1
          }
          END { exit found ? 0 : 1 }
        '
    }

    sealing_active_in_config() {
      [ "$(journald_effective_seal)" = "yes" ]
    }

    activation_state_value() {
      [ -r "$ACTIVATION_STATE_FILE" ] || return 0
      awk -F '\t' 'NR == 1 { print $1 }' "$ACTIVATION_STATE_FILE"
    }

    activation_state_boot_id() {
      [ -r "$ACTIVATION_STATE_FILE" ] || return 0
      awk -F '\t' 'NR == 1 { print $2 }' "$ACTIVATION_STATE_FILE"
    }

    activation_baseline_boot_id() {
      [ -r "$FSS_BOOT_BASELINE_FILE" ] || return 0
      tr -d '[:space:]' < "$FSS_BOOT_BASELINE_FILE"
    }

    activation_mode_enabled() {
      local state

      state="$(activation_state_value)"
      [ "$state" = "disabled" ] && return 1
      [ -n "$state" ] && return 0
      if journald_config_has_seal_no || [ -f /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf ]; then
        return 0
      fi
      return 1
    }

    run_activation_preflight() {
      local activation_state=""
      local activation_boot_id=""
      local baseline_boot_id=""
      local exit_code=0

      FSS_VERDICT=verified
      FSS_VERDICT_TAGS="ACTIVATION_DISABLED"
      FSS_VERDICT_REASON="activation mode disabled"

      if activation_mode_enabled; then
        activation_state="$(activation_state_value)"
        activation_boot_id="$(activation_state_boot_id)"
        baseline_boot_id="$(activation_baseline_boot_id)"
        FSS_VERDICT_TAGS="ACTIVATION_ACTIVE"
        FSS_VERDICT_REASON="activation active for current boot"

        if [ "$activation_state" = "failed" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_FAILED"
          FSS_VERDICT_REASON="FSS sealing was not activated"
          exit_code=1
        elif [ "$activation_state" != "active" ] \
          || [ "$activation_boot_id" != "$CURRENT_BOOT_ID" ] \
          || [ "$baseline_boot_id" != "$CURRENT_BOOT_ID" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_STALE"
          FSS_VERDICT_REASON="FSS activation state is not active for current boot"
          exit_code=1
        elif ! sealing_active_in_config; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_FAILED"
          FSS_VERDICT_REASON="effective journald Seal setting is not yes"
          exit_code=1
        fi
      fi

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "activation-preflight" "$exit_code" "$FSS_VERDICT" "$FSS_VERDICT_TAGS" "$FSS_VERDICT_REASON" \
        >> "$VERIFY_SUMMARY"

      if [ "$FSS_VERDICT" = "fail" ]; then
        CRITICAL_FAILURE=1
      fi
    }

    refresh_fss_allowlists() {
      PRE_FSS_ARCHIVE="$(read_file_if_present "$STATE_DIR/fss-pre-fss-archive" | tr -d '[:space:]')"
      RECOVERY_ARCHIVES="$(fss_read_recorded_archive_list "$STATE_DIR/fss-recovery-archives")"
      RAW_RECOVERY_RECEIPTS="$(fss_read_receipts "$STATE_DIR/fss-recovery-receipts")"
      RECOVERY_RECEIPT_MISMATCHES="$(fss_receipt_mismatches "$RAW_RECOVERY_RECEIPTS")"
      RECOVERY_RECEIPTS="$(fss_filter_valid_receipts "$RAW_RECOVERY_RECEIPTS")"
      RAW_PRE_ACTIVATION_RECEIPTS="$(fss_read_pre_activation_receipts "$STATE_DIR/fss-pre-activation-receipts")"
      PRE_ACTIVATION_RECEIPT_MISMATCHES="$(fss_pre_activation_receipt_mismatches "$RAW_PRE_ACTIVATION_RECEIPTS")"
      PRE_ACTIVATION_RECEIPTS="$(fss_filter_valid_receipts "$RAW_PRE_ACTIVATION_RECEIPTS")"
      RAW_UNCLEAN_RECEIPTS="$(fss_read_unclean_shutdown_receipts "$STATE_DIR/fss-unclean-shutdown-receipts")"
      UNCLEAN_RECEIPT_MISMATCHES="$(fss_unclean_shutdown_receipt_mismatches "$RAW_UNCLEAN_RECEIPTS")"
      UNCLEAN_RECEIPTS="$(fss_filter_valid_receipts "$RAW_UNCLEAN_RECEIPTS")"
    }

    fss_receipt_missing_paths() {
      local records="$1"
      local rec ver path rest missing=""

      while IFS= read -r rec || [ -n "$rec" ]; do
        [ -n "$rec" ] || continue
        # shellcheck disable=SC2034  # ver/rest are positional placeholders
        IFS=$'\t' read -r ver path rest <<<"$rec"
        [ -n "$path" ] || continue
        [ -e "$path" ] && continue
        missing=$(fss_append_unique_line "$missing" "$path")
      done <<<"$records"

      printf '%s' "$missing"
    }

    fss_receipt_count_for_boot() {
      local records="$1"
      local wanted_boot="$2"
      local mode="$3"
      local rec ver path inode size boot rest
      local count=0

      [ -n "$wanted_boot" ] || { printf '0'; return 0; }
      while IFS= read -r rec || [ -n "$rec" ]; do
        [ -n "$rec" ] || continue
        # shellcheck disable=SC2034  # ver/path/inode/size/rest are positional placeholders
        IFS=$'\t' read -r ver path inode size boot rest <<<"$rec"
        case "$mode" in
        current)
          [ "$boot" = "$wanted_boot" ] && count=$((count + 1))
          ;;
        stale)
          [ -n "$boot" ] && [ "$boot" != "$wanted_boot" ] && count=$((count + 1))
          ;;
        esac
      done <<<"$records"

      printf '%s' "$count"
    }

    write_receipt_summary() {
      local class="$1"
      local raw="$2"
      local valid="$3"
      local mismatches="$4"
      local missing

      missing="$(fss_receipt_missing_paths "$raw")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$class" \
        "$(fss_count_nonempty_lines "$raw")" \
        "$(fss_count_nonempty_lines "$valid")" \
        "$(fss_receipt_count_for_boot "$valid" "$CURRENT_BOOT_ID" current)" \
        "$(fss_receipt_count_for_boot "$valid" "$CURRENT_BOOT_ID" stale)" \
        "$(fss_count_nonempty_lines "$missing")" \
        "$(fss_count_nonempty_lines "$mismatches")" \
        >> "$RECEIPT_SUMMARY"
    }

    refresh_receipt_summary() {
      printf 'class\ttotal\tvalid\tcurrent\tstale\tmissing\tmismatched\n' > "$RECEIPT_SUMMARY"
      write_receipt_summary "recovery" "$RAW_RECOVERY_RECEIPTS" "$RECOVERY_RECEIPTS" "$RECOVERY_RECEIPT_MISMATCHES"
      write_receipt_summary "pre-activation" "$RAW_PRE_ACTIVATION_RECEIPTS" "$PRE_ACTIVATION_RECEIPTS" "$PRE_ACTIVATION_RECEIPT_MISMATCHES"
      write_receipt_summary "unclean-shutdown" "$RAW_UNCLEAN_RECEIPTS" "$UNCLEAN_RECEIPTS" "$UNCLEAN_RECEIPT_MISMATCHES"
    }

    classify_verify_file() {
      local name="$1"
      local output_file="$2"
      local exit_code="$3"
      local expected_pre="$4"
      local recovery_receipts="$5"
      local pre_activation_receipts="$6"
      local current_boot="$7"
      local unclean_receipts="$8"

      local verify_output
      verify_output="$(cat "$output_file")"
      fss_classify_verify_output "$verify_output"
      fss_verify_policy_decision "$expected_pre" "$recovery_receipts" "$pre_activation_receipts" "$current_boot" "$exit_code" "$unclean_receipts"
      if [ -n "$RECOVERY_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "RECOVERY_RECEIPT_MISMATCH")
        FSS_VERDICT_REASON="recovery receipt content mismatch"
      elif [ -n "$PRE_ACTIVATION_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_RECEIPT_MISMATCH")
        FSS_VERDICT_REASON="pre-activation receipt content mismatch"
      elif [ -n "$UNCLEAN_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN_RECEIPT_MISMATCH")
        FSS_VERDICT_REASON="unclean-shutdown receipt content mismatch"
      fi

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$exit_code" "$FSS_VERDICT" "$FSS_VERDICT_TAGS" "$FSS_VERDICT_REASON" \
        >> "$VERIFY_SUMMARY"

      if [ "$FSS_VERDICT" = "fail" ]; then
        CRITICAL_FAILURE=1
      fi
    }

    run_verify_capture() {
      local name="$1"
      shift
      local output="$OUTPUT_DIR/verify/$name.txt"
      local rc

      set +e
      "$@" >"$output" 2>&1
      rc=$?
      set -e

      append_command_log "verify/$name" "$rc" "$@"
      refresh_fss_allowlists
      classify_verify_file "$name" "$output" "$rc" "$PRE_FSS_ARCHIVE" "$RECOVERY_RECEIPTS" "$PRE_ACTIVATION_RECEIPTS" "$CURRENT_BOOT_ID" "$UNCLEAN_RECEIPTS"
      return 0
    }

    run_per_file_verify() {
      local label="$1"
      local journal_path="$2"
      local output="$OUTPUT_DIR/verify/per-file-$label.tsv"
      local file safe_name rc verify_output_file

      printf 'path\texit_code\tverdict\ttags\treason\n' > "$output"

      while IFS= read -r file || [ -n "$file" ]; do
        [ -n "$file" ] || continue
        safe_name="$(printf '%s' "$file" | sed 's#[^A-Za-z0-9._-]#_#g')"
        verify_output_file="$OUTPUT_DIR/verify/per-file-$label-$safe_name.txt"

        set +e
        if [ -n "$VERIFY_KEY" ]; then
          journalctl --file="$file" --verify --verify-key="$VERIFY_KEY" >"$verify_output_file" 2>&1
        else
          journalctl --file="$file" --verify >"$verify_output_file" 2>&1
        fi
        rc=$?
        set -e

        fss_classify_verify_output "$(cat "$verify_output_file")"
        fss_verify_policy_decision "$PRE_FSS_ARCHIVE" "$RECOVERY_RECEIPTS" "$PRE_ACTIVATION_RECEIPTS" "$CURRENT_BOOT_ID" "$rc" "$UNCLEAN_RECEIPTS"
        if [ -n "$RECOVERY_RECEIPT_MISMATCHES" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "RECOVERY_RECEIPT_MISMATCH")
          FSS_VERDICT_REASON="recovery receipt content mismatch"
        elif [ -n "$PRE_ACTIVATION_RECEIPT_MISMATCHES" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_RECEIPT_MISMATCH")
          FSS_VERDICT_REASON="pre-activation receipt content mismatch"
        elif [ -n "$UNCLEAN_RECEIPT_MISMATCHES" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN_RECEIPT_MISMATCH")
          FSS_VERDICT_REASON="unclean-shutdown receipt content mismatch"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' \
          "$file" "$rc" "$FSS_VERDICT" "$FSS_VERDICT_TAGS" "$FSS_VERDICT_REASON" \
          >> "$output"

        if [ "$FSS_VERDICT" = "fail" ]; then
          CRITICAL_FAILURE=1
        fi
      done < <(find "$journal_path" -maxdepth 1 -type f \( -name '*.journal' -o -name '*.journal~' \) -print 2>/dev/null | sort)
    }

    MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || true)"
    if [ -z "$MACHINE_ID" ]; then
      warn "Cannot read /etc/machine-id"
      MACHINE_ID="unknown-machine-id"
    fi
    CURRENT_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot)"

    STATE_DIR="/var/log/journal/$MACHINE_ID"
    RUNTIME_STATE_DIR="/run/log/journal/$MACHINE_ID"
    FSS_CONFIG="$STATE_DIR/fss-config"
    FSS_BOOT_BASELINE_FILE="$STATE_DIR/fss-baseline-boot"
    ACTIVATION_STATE_FILE="$STATE_DIR/fss-activation-state"
    KEY_DIR=""
    if [ -s "$FSS_CONFIG" ]; then
      KEY_DIR="$(cat "$FSS_CONFIG")"
    else
      for candidate in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do
        if [ -d "$candidate" ]; then
          KEY_DIR="$candidate"
          break
        fi
      done
    fi

    VERIFY_KEY_PATH=""
    VERIFY_KEY=""
    if [ -n "$KEY_DIR" ] && [ -r "$KEY_DIR/verification-key" ] && [ -s "$KEY_DIR/verification-key" ]; then
      VERIFY_KEY_PATH="$KEY_DIR/verification-key"
      VERIFY_KEY="$(cat "$VERIFY_KEY_PATH")"
    fi

    refresh_fss_allowlists
    refresh_receipt_summary

    info "Writing FSS triage data to $OUTPUT_DIR"

    {
      printf 'timestamp_utc=%s\n' "$TIMESTAMP"
      printf 'hostname=%s\n' "$HOSTNAME"
      printf 'machine_id=%s\n' "$MACHINE_ID"
      printf 'state_dir=%s\n' "$STATE_DIR"
      printf 'runtime_state_dir=%s\n' "$RUNTIME_STATE_DIR"
      printf 'key_dir=%s\n' "''${KEY_DIR:-unknown}"
      printf 'verification_key_path=%s\n' "''${VERIFY_KEY_PATH:-missing}"
      printf 'pre_fss_archive=%s\n' "''${PRE_FSS_ARCHIVE:-none}"
      printf 'recovery_archives_count=%s\n' "$(fss_count_nonempty_lines "$RECOVERY_ARCHIVES")"
      printf 'recovery_receipts_count=%s\n' "$(fss_count_nonempty_lines "$RECOVERY_RECEIPTS")"
      printf 'recovery_receipt_mismatches_count=%s\n' "$(fss_count_nonempty_lines "$RECOVERY_RECEIPT_MISMATCHES")"
      printf 'pre_activation_receipts_count=%s\n' "$(fss_count_nonempty_lines "$PRE_ACTIVATION_RECEIPTS")"
      printf 'pre_activation_receipt_mismatches_count=%s\n' "$(fss_count_nonempty_lines "$PRE_ACTIVATION_RECEIPT_MISMATCHES")"
      printf 'unclean_shutdown_receipts_count=%s\n' "$(fss_count_nonempty_lines "$UNCLEAN_RECEIPTS")"
      printf 'unclean_shutdown_receipt_mismatches_count=%s\n' "$(fss_count_nonempty_lines "$UNCLEAN_RECEIPT_MISMATCHES")"
      printf 'current_boot_id=%s\n' "$CURRENT_BOOT_ID"
      if activation_mode_enabled; then
        printf 'activation_mode=enabled\n'
      else
        printf 'activation_mode=disabled\n'
      fi
      printf 'journald_effective_seal=%s\n' "$(journald_effective_seal)"
      activation_state_raw="$(read_file_if_present "$ACTIVATION_STATE_FILE")"
      printf 'activation_state=%s\n' "$(printf '%s\n' "$activation_state_raw" | awk -F '\t' 'NR == 1 { print $1 }')"
      printf 'activation_boot_id=%s\n' "$(printf '%s\n' "$activation_state_raw" | awk -F '\t' 'NR == 1 { print $2 }')"
      printf 'activation_baseline_boot_id=%s\n' "$(activation_baseline_boot_id)"
      printf 'activation_state_raw=%s\n' "$activation_state_raw"
      printf 'sync_before_verify=%s\n' "$DO_SYNC"
      printf 'recovery_probe=%s\n' "$DO_RECOVERY_PROBE"
      printf 'journald_restart_probe=%s\n' "$DO_JOURNALD_RESTART_PROBE"
    } > "$OUTPUT_DIR/context.env"

    run_activation_preflight

    run_capture "date-utc" date -u
    run_capture "hostnamectl" hostnamectl
    run_capture "uname" uname -a
    run_capture "uptime" uptime
    run_capture "journalctl-version" journalctl --version
    run_capture "journalctl-list-boots" journalctl --list-boots
    run_capture "journalctl-disk-usage" journalctl --disk-usage
    run_capture "timedatectl-status" timedatectl status
    run_capture "timedatectl-sync-state" timedatectl show -p NTPSynchronized
    run_capture "findmnt" findmnt
    run_capture "df-journal" df -h /var/log/journal /run/log/journal

    run_shell_capture "journald-cat-config" "systemd-analyze cat-config systemd/journald.conf"
    run_shell_capture "journald-config-snippets" "for d in /etc/systemd/journald.conf.d /run/systemd/journald.conf.d /usr/lib/systemd/journald.conf.d; do [ -d \"\$d\" ] && find \"\$d\" -maxdepth 1 -type f -print -exec sed -n '1,120p' {} \\;; done"
    run_shell_capture "clocksource" "for p in /sys/devices/system/clocksource/clocksource0/current_clocksource /sys/devices/system/clocksource/clocksource0/available_clocksource; do [ -r \"\$p\" ] && printf '%s: %s\\n' \"\$p\" \"\$(cat \"\$p\")\"; done"
    run_shell_capture "journal-files-stat" "for d in '$STATE_DIR' '$RUNTIME_STATE_DIR'; do [ -d \"\$d\" ] || continue; find \"\$d\" -maxdepth 1 -type f -printf '%p\\t%i\\t%s\\t%TY-%Tm-%TdT%TH:%TM:%TS%TZ\\t%m\\t%u\\t%g\\n' | sort; done"
    run_shell_capture "fss-state-files" "for p in '$STATE_DIR/fss' '$RUNTIME_STATE_DIR/fss' '$STATE_DIR/fss-rotated' '$STATE_DIR/fss-baseline-boot' '$STATE_DIR/fss-pre-fss-archive' '$STATE_DIR/fss-recovery-archives' '$STATE_DIR/fss-recovery-receipts' '$STATE_DIR/fss-pre-activation-receipts' '$STATE_DIR/fss-unclean-shutdown-receipts' '$STATE_DIR/fss-activation-state' '$FSS_CONFIG' '$KEY_DIR/initialized' '$VERIFY_KEY_PATH' /run/ghaf-clock-ready /run/ghaf-clock-ready-state /run/ghaf-clock-synced /run/ghaf-clock-sync-state /var/lib/ghaf/clock-ready/last-good-realtime; do [ -n \"\$p\" ] && [ -e \"\$p\" ] && stat -c '%n\\t%i\\t%s\\t%Y\\t%F\\t%m\\t%U\\t%G\\t%A' \"\$p\"; done"
    run_shell_capture "fss-state-content" "for p in '$STATE_DIR/fss-pre-fss-archive' '$STATE_DIR/fss-recovery-archives' '$STATE_DIR/fss-recovery-receipts' '$STATE_DIR/fss-pre-activation-receipts' '$STATE_DIR/fss-unclean-shutdown-receipts' '$STATE_DIR/fss-activation-state' /run/ghaf-clock-ready-state /run/ghaf-clock-sync-state /var/lib/ghaf/clock-ready/last-good-realtime; do [ -r \"\$p\" ] && { printf '===== %s =====\\n' \"\$p\"; sed -n '1,200p' \"\$p\"; }; done"

    capture_boot_logs() {
      local label="$1"
      local boot="$2"

      run_shell_capture "fss-unit-logs-$label" "journalctl -u systemd-journald.service -u systemd-journal-flush.service -u ghaf-clock-ready.service -u ghaf-clock-sync.service -u journal-fss-setup.service -u journal-fss-verify.service -u ghaf-clock-jump-watcher.service -u ghaf-journal-alloy-recover.service -u alloy.service -b $boot --no-pager"
      run_shell_capture "journal-errors-$label" "journalctl -p warning..alert -b $boot --no-pager"
      run_shell_capture "audit-fss-events-$label" "journalctl -g 'journal_fss_keys|journal_sealed_logs|AUDIT_LOG_INTEGRITY_FAIL|AUDIT_LOG_VERIFY_COMPLETED' -b $boot --no-pager"
    }

    for unit in \
      systemd-journald.service \
      systemd-journal-flush.service \
      ghaf-clock-ready.service \
      journal-fss-setup.service \
      journal-fss-verify.service \
      journal-fss-verify.timer \
      ghaf-clock-jump-watcher.service \
      ghaf-journal-alloy-recover.service \
      alloy.service; do
      safe_unit="$(printf '%s' "$unit" | sed 's#[^A-Za-z0-9._-]#_#g')"
      run_shell_capture "units/$safe_unit-show" "systemctl show '$unit' --no-pager"
      run_shell_capture "units/$safe_unit-status" "systemctl status '$unit' --no-pager -l"
      run_shell_capture "units/$safe_unit-cat" "systemctl cat '$unit' --no-pager"
    done

    capture_boot_logs "previous" "-1"
    capture_boot_logs "current" "0"

    if [ -z "$VERIFY_KEY" ]; then
      warn "Verification key is unavailable; FSS authenticity verification will be skipped."
      run_verify_capture "default-no-key-before-sync" journalctl --verify
    else
      run_verify_capture "default-with-key-before-sync" journalctl --verify --verify-key="$VERIFY_KEY"
    fi

    if [ "$DO_SYNC" -eq 1 ]; then
      run_capture "journalctl-sync" journalctl --sync
      if [ -n "$VERIFY_KEY" ]; then
        run_verify_capture "default-with-key-after-sync" journalctl --verify --verify-key="$VERIFY_KEY"
      else
        run_verify_capture "default-no-key-after-sync" journalctl --verify
      fi
    fi

    if [ -d "$STATE_DIR" ]; then
      run_per_file_verify "persistent" "$STATE_DIR"
    fi
    if [ -d "$RUNTIME_STATE_DIR" ]; then
      run_per_file_verify "runtime" "$RUNTIME_STATE_DIR"
    fi

    if [ "$DO_RECOVERY_PROBE" -eq 1 ]; then
      warn "Running recovery probe: starting ghaf-journal-alloy-recover.service"
      run_capture "probe-recovery-start" systemctl start ghaf-journal-alloy-recover.service
      run_capture "probe-recovery-sync" journalctl --sync
      if [ -n "$VERIFY_KEY" ]; then
        run_verify_capture "probe-recovery-with-key-after-sync" journalctl --verify --verify-key="$VERIFY_KEY"
      else
        run_verify_capture "probe-recovery-no-key-after-sync" journalctl --verify
      fi
    fi

    if [ "$DO_JOURNALD_RESTART_PROBE" -eq 1 ]; then
      warn "Running journald restart probe: restarting systemd-journald.service twice"
      run_capture "probe-journald-restart-1" systemctl restart systemd-journald.service
      sleep 2
      run_capture "probe-journald-restart-2" systemctl restart systemd-journald.service
      run_capture "probe-journald-sync" journalctl --sync
      if [ -n "$VERIFY_KEY" ]; then
        run_verify_capture "probe-journald-restart-with-key-after-sync" journalctl --verify --verify-key="$VERIFY_KEY"
      else
        run_verify_capture "probe-journald-restart-no-key-after-sync" journalctl --verify
      fi
    fi

    {
      refresh_receipt_summary
      echo "FSS triage summary"
      echo
      cat "$OUTPUT_DIR/context.env"
      echo
      echo "Verification summary:"
      column -t -s $'\t' "$VERIFY_SUMMARY" 2>/dev/null || cat "$VERIFY_SUMMARY"
      echo
      echo "Receipt summary:"
      column -t -s $'\t' "$RECEIPT_SUMMARY" 2>/dev/null || cat "$RECEIPT_SUMMARY"
      echo
      echo "Command log:"
      column -t -s $'\t' "$COMMAND_LOG" 2>/dev/null || cat "$COMMAND_LOG"
      echo
      echo "Diagnostics directory: $OUTPUT_DIR"
    } > "$SUMMARY"

    cat "$SUMMARY"

    if [ "$CRITICAL_FAILURE" -eq 1 ]; then
      warn "Critical verification failures were observed. See $VERIFY_SUMMARY and $OUTPUT_DIR/verify/."
      if [ "$STRICT_EXIT" -eq 1 ]; then
        exit 1
      fi
    else
      pass "No critical verification verdicts observed by the triage script."
    fi
  '';
}
