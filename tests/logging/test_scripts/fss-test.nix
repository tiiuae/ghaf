# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS (Forward Secure Sealing) Hardware Test Script
#
# Verifies FSS functionality on a deployed Ghaf system. On failure,
# the raw `journalctl --verify` output is printed so an operator can
# inspect which journal files failed.
#
# Usage:
#   Build:   nix build .#checks.x86_64-linux.fss-test
#   Deploy:  scp result/bin/fss-test root@ghaf-host:/tmp/
#   Run:     ssh root@ghaf-host /tmp/fss-test
#
# Tests performed:
#   1. FSS setup service status
#   2. Sealing key existence
#   3. Verification key extraction
#   4. Initialization sentinel
#   5. Journal integrity verification (via shared policy)
#   6. Verification timer status
#   7. Audit rules configuration
#
# Exit codes:
#   0 - All critical tests passed (warnings may be present)
#   1 - One or more critical tests failed
#
{
  writeShellApplication,
  coreutils,
  systemd,
  gnugrep,
  gawk,
}:
let
  verifyClassifierLib = builtins.readFile ../../../modules/common/logging/fss-verify-classifier.sh;
in
writeShellApplication {
  name = "fss-test";
  runtimeInputs = [
    coreutils
    systemd
    gnugrep
    gawk
  ];
  # Shared classifier library: some helper functions are unused in this consumer.
  excludeShellChecks = [ "SC2329" ];
  text = ''
    ${verifyClassifierLib}

    PASSED=0
    FAILED=0
    WARNED=0

    pass() { fss_log pass "$1"; PASSED=$((PASSED + 1)); }
    fail() { fss_log fail "$1"; FAILED=$((FAILED + 1)); }
    warn() { fss_log warn "$1"; WARNED=$((WARNED + 1)); }
    info() { fss_log info "$1"; }

    fss_log_block <<'EOF'
    ==========================================
      FSS (Forward Secure Sealing) Test Suite
    ==========================================
    EOF

    MACHINE_ID=$(cat /etc/machine-id)
    HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown-host)"
    FSS_KEY="/var/log/journal/$MACHINE_ID/fss"
    FSS_KEY_VOLATILE="/run/log/journal/$MACHINE_ID/fss"
    FSS_CONFIG="/var/log/journal/$MACHINE_ID/fss-config"
    PRE_FSS_ARCHIVE_FILE="/var/log/journal/$MACHINE_ID/fss-pre-fss-archive"
    RECOVERY_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-recovery-receipts"
    PRE_ACTIVATION_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-pre-activation-receipts"
    UNCLEAN_SHUTDOWN_RECEIPTS_FILE="/var/log/journal/$MACHINE_ID/fss-unclean-shutdown-receipts"
    ACTIVATION_STATE_FILE="/var/log/journal/$MACHINE_ID/fss-activation-state"
    FSS_BOOT_BASELINE_FILE="/var/log/journal/$MACHINE_ID/fss-baseline-boot"
    CURRENT_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot)"
    ACTIVATION_MODE=0
    if systemd-analyze cat-config systemd/journald.conf 2>/dev/null |
      grep -iqE '^[[:space:]]*Seal[[:space:]]*=[[:space:]]*no'; then
      ACTIVATION_MODE=1
    fi

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

    # Test 1: FSS setup service
    info "Test 1: Checking journal-fss-setup service..."
    if systemctl cat journal-fss-setup.service &>/dev/null; then
      RESULT=$(systemctl show journal-fss-setup --property=Result --value 2>/dev/null)
      STATE=$(systemctl show journal-fss-setup --property=ActiveState --value 2>/dev/null)
      if [ "$RESULT" = "success" ] || [ "$STATE" = "active" ]; then
        pass "journal-fss-setup service completed successfully"
      else
        warn "journal-fss-setup service status: state=$STATE result=$RESULT"
      fi
    elif [ -f "$FSS_KEY" ] || [ -f "$FSS_KEY_VOLATILE" ]; then
      pass "journal-fss-setup service ran (FSS key exists)"
    else
      fail "journal-fss-setup service not found - FSS may not be enabled"
    fi

    # Test 2: Sealing key
    info "Test 2: Checking FSS sealing key..."
    if [ -f "$FSS_KEY" ]; then
      pass "FSS sealing key exists at $FSS_KEY"
    elif [ -f "$FSS_KEY_VOLATILE" ]; then
      warn "FSS key in volatile storage: $FSS_KEY_VOLATILE (lost on reboot)"
    else
      fail "FSS sealing key not found in persistent or volatile storage"
    fi

    # Discover KEY_DIR from fss-config pointer, falling back to hostname paths.
    KEY_DIR=""
    if [ -s "$FSS_CONFIG" ]; then
      KEY_DIR=$(cat "$FSS_CONFIG")
      info "Key directory (from fss-config): $KEY_DIR"
    else
      for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do
        if [ -d "$CANDIDATE" ]; then
          KEY_DIR="$CANDIDATE"
          info "Key directory (from hostname fallback): $KEY_DIR"
          break
        fi
      done
    fi

    # Test 3: Verification key
    info "Test 3: Checking verification key..."
    VERIFY_KEY_PATH=""
    VERIFY_KEY=""
    KEY_DIR_INACCESSIBLE=0
    if [ -n "$KEY_DIR" ] && [ ! -x "$KEY_DIR" ]; then
      KEY_DIR_INACCESSIBLE=1
      if [ "$(id -u)" -eq 0 ]; then
        fail "Key directory is not searchable at $KEY_DIR"
      else
        warn "Key directory is not searchable as $(id -un); rerun fss-test as root"
      fi
    elif [ -n "$KEY_DIR" ] && [ -e "$KEY_DIR/verification-key" ]; then
      VERIFY_KEY_PATH="$KEY_DIR/verification-key"
      if [ -s "$VERIFY_KEY_PATH" ] && [ -r "$VERIFY_KEY_PATH" ]; then
        pass "Verification key exists at $VERIFY_KEY_PATH"
        VERIFY_KEY=$(cat "$VERIFY_KEY_PATH")
      elif [ "$(id -u)" -eq 0 ]; then
        fail "Verification key exists but is unreadable/empty at $VERIFY_KEY_PATH"
      else
        warn "Verification key unreadable as $(id -un); rerun fss-test as root"
      fi
    elif [ -n "$KEY_DIR" ]; then
      fail "Verification key not found at $KEY_DIR/verification-key"
    else
      warn "Key directory could not be discovered"
    fi

    # Test 4: Initialization sentinel
    info "Test 4: Checking initialization sentinel..."
    if [ "$KEY_DIR_INACCESSIBLE" = 1 ]; then
      warn "Initialization sentinel unavailable because key directory is not searchable"
    elif [ -n "$KEY_DIR" ] && [ -f "$KEY_DIR/initialized" ]; then
      pass "Initialization sentinel exists at $KEY_DIR/initialized"
    else
      warn "Initialization sentinel not found"
    fi

    # Test 5: Journal verification (shared policy)
    info "Test 5: Running journal verification..."
    if [ -z "$VERIFY_KEY" ]; then
      warn "Skipping verification (verification key unavailable)"
    else
      if ! journalctl --sync >/dev/null 2>&1; then
        warn "journalctl --sync failed before verification"
      fi
      VERIFY_EXIT=0
      VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?
      FSS_VERDICT=""
      FSS_VERDICT_TAGS=""
      FSS_VERDICT_REASON=""
      RAW_PRE_ACTIVATION_RECEIPTS=$(fss_read_pre_activation_receipts "$PRE_ACTIVATION_RECEIPTS_FILE")
      RAW_RECOVERY_RECEIPTS=$(fss_read_receipts "$RECOVERY_RECEIPTS_FILE")
      RAW_UNCLEAN_RECEIPTS=$(fss_read_unclean_shutdown_receipts "$UNCLEAN_SHUTDOWN_RECEIPTS_FILE")
      RECOVERY_RECEIPT_MISMATCHES=$(fss_receipt_mismatches "$RAW_RECOVERY_RECEIPTS")
      PRE_ACTIVATION_RECEIPT_MISMATCHES=$(fss_pre_activation_receipt_mismatches "$RAW_PRE_ACTIVATION_RECEIPTS")
      UNCLEAN_RECEIPT_MISMATCHES=$(fss_unclean_shutdown_receipt_mismatches "$RAW_UNCLEAN_RECEIPTS")
      if [ "$ACTIVATION_MODE" = 1 ]; then
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
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_FAILED"
          FSS_VERDICT_REASON="FSS sealing was not activated"
        elif [ "$ACTIVATION_STATE" != "active" ] \
          || [ "$ACTIVATION_BOOT_ID" != "$CURRENT_BOOT_ID" ] \
          || [ "$ACTIVATION_BASELINE_BOOT_ID" != "$CURRENT_BOOT_ID" ]; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_STALE"
          FSS_VERDICT_REASON="FSS activation state is not active for current boot"
        elif ! sealing_active_in_config; then
          FSS_VERDICT=fail
          FSS_VERDICT_TAGS="ACTIVATION_FAILED"
          FSS_VERDICT_REASON="effective journald Seal setting is not yes"
        fi
      fi

      if [ -z "$FSS_VERDICT" ] && [ -n "$RECOVERY_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS="RECOVERY_RECEIPT_MISMATCH"
        FSS_VERDICT_REASON="recovery receipt content mismatch"
      elif [ -z "$FSS_VERDICT" ] && [ -n "$PRE_ACTIVATION_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS="PRE_ACTIVATION_RECEIPT_MISMATCH"
        FSS_VERDICT_REASON="pre-activation receipt content mismatch"
      elif [ -z "$FSS_VERDICT" ] && [ -n "$UNCLEAN_RECEIPT_MISMATCHES" ]; then
        FSS_VERDICT=fail
        FSS_VERDICT_TAGS="UNCLEAN_SHUTDOWN_RECEIPT_MISMATCH"
        FSS_VERDICT_REASON="unclean-shutdown receipt content mismatch"
      elif [ -z "$FSS_VERDICT" ]; then
        fss_classify_verify_output "$VERIFY_OUTPUT"
        fss_verify_policy_decision \
          "$(fss_read_recorded_pre_fss_archive "$PRE_FSS_ARCHIVE_FILE")" \
          "$(fss_filter_valid_receipts "$RAW_RECOVERY_RECEIPTS")" \
          "$(fss_filter_valid_receipts "$RAW_PRE_ACTIVATION_RECEIPTS")" \
          "$CURRENT_BOOT_ID" \
          "$VERIFY_EXIT" \
          "$(fss_filter_valid_receipts "$RAW_UNCLEAN_RECEIPTS")"
      fi

      case "$FSS_VERDICT" in
      verified)
        if [ -n "$FSS_VERDICT_REASON" ]; then
          pass "Journal verification verified ($FSS_VERDICT_REASON)"
        else
          pass "Journal verification verified"
        fi
        ;;
      verified-with-exception)
        pass "Journal verification verified with recorded exception [$FSS_VERDICT_TAGS] ($FSS_VERDICT_REASON)"
        ;;
      warning)
        warn "Journal verification WARNING [$FSS_VERDICT_TAGS] ($FSS_VERDICT_REASON)"
        echo "   Output: $VERIFY_OUTPUT"
        ;;
      fail)
        fail "Journal verification FAILED [$FSS_VERDICT_TAGS] ($FSS_VERDICT_REASON)"
        [ -n "''${RECOVERY_RECEIPT_MISMATCHES:-}" ] &&
          echo "   Mismatched recovery receipts: $RECOVERY_RECEIPT_MISMATCHES"
        [ -n "''${PRE_ACTIVATION_RECEIPT_MISMATCHES:-}" ] &&
          echo "   Mismatched pre-activation receipts: $PRE_ACTIVATION_RECEIPT_MISMATCHES"
        [ -n "''${UNCLEAN_RECEIPT_MISMATCHES:-}" ] &&
          echo "   Mismatched unclean-shutdown receipts: $UNCLEAN_RECEIPT_MISMATCHES"
        echo "   Output: $VERIFY_OUTPUT"
        ;;
      esac
      [ "$VERIFY_EXIT" -ne 0 ] && [ "$FSS_VERDICT" != "fail" ] &&
        info "journalctl --verify returned exit $VERIFY_EXIT with no critical errors"
    fi

    # Test 6: Verification timer
    info "Test 6: Checking verification timer..."
    if systemctl cat journal-fss-verify.timer &>/dev/null; then
      if systemctl is-active --quiet journal-fss-verify.timer; then
        pass "journal-fss-verify.timer is active"
        NEXT_RUN=$(systemctl list-timers journal-fss-verify --no-pager 2>/dev/null | grep journal-fss-verify | awk '{print $1, $2}' || true)
        [ -n "$NEXT_RUN" ] && echo "   Next run: $NEXT_RUN"
      else
        warn "journal-fss-verify.timer exists but is not active"
      fi
    else
      warn "journal-fss-verify.timer not found"
    fi

    # Test 7: Audit rules
    info "Test 7: Checking audit rules..."
    if command -v auditctl &>/dev/null; then
      AUDITCTL_OUTPUT=""
      if AUDITCTL_OUTPUT=$(auditctl -l 2>&1); then
        RULES="$AUDITCTL_OUTPUT"
      elif [ "$(id -u)" -ne 0 ]; then
        warn "Audit rules unreadable as $(id -un); rerun fss-test as root"
        RULES=""
      else
        warn "Could not list audit rules: $AUDITCTL_OUTPUT"
        RULES=""
      fi

      if [ -n "$RULES" ] && echo "$RULES" | grep -q "journal_fss_keys\|journal_sealed_logs"; then
        pass "FSS audit rules are configured"
      elif [ -n "$RULES" ] && echo "$RULES" | grep -q "No rules"; then
        warn "No audit rules configured (auditd may not be enabled)"
      elif [ -n "$RULES" ]; then
        warn "FSS-specific audit rules not found"
      fi
    else
      warn "auditctl not available, skipping audit check"
    fi

    # Summary
    fss_log_block <<'EOF'

    ==========================================
      FSS Test Suite Complete
    ==========================================
    EOF
    printf "  %bPassed:%b  %s\n" "$GREEN" "$NC" "$PASSED"
    printf "  %bFailed:%b  %s\n" "$RED" "$NC" "$FAILED"
    printf "  %bWarned:%b  %s\n\n" "$YELLOW" "$NC" "$WARNED"

    if [ "$FAILED" -gt 0 ]; then
      printf "%bSome tests failed. FSS may not be working correctly.%b\n" "$RED" "$NC"
      exit 1
    elif [ "$WARNED" -gt 0 ]; then
      printf "%bAll critical tests passed, but some warnings were raised.%b\n" "$YELLOW" "$NC"
    else
      printf "%bAll tests passed. FSS is working correctly.%b\n" "$GREEN" "$NC"
    fi
  '';
}
