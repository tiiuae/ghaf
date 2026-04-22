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
  ];
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
    FSS_KEY="/var/log/journal/$MACHINE_ID/fss"
    FSS_KEY_VOLATILE="/run/log/journal/$MACHINE_ID/fss"
    FSS_CONFIG="/var/log/journal/$MACHINE_ID/fss-config"
    PRE_FSS_ARCHIVE_FILE="/var/log/journal/$MACHINE_ID/fss-pre-fss-archive"
    RECOVERY_ARCHIVES_FILE="/var/log/journal/$MACHINE_ID/fss-recovery-archives"

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
      for CANDIDATE in "/persist/common/journal-fss/$(hostname)" "/etc/common/journal-fss/$(hostname)"; do
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
    if [ -n "$KEY_DIR" ] && [ -e "$KEY_DIR/verification-key" ]; then
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
    if [ -n "$KEY_DIR" ] && [ -f "$KEY_DIR/initialized" ]; then
      pass "Initialization sentinel exists at $KEY_DIR/initialized"
    else
      warn "Initialization sentinel not found"
    fi

    # Test 5: Journal verification (shared policy)
    info "Test 5: Running journal verification..."
    if [ -z "$VERIFY_KEY" ]; then
      warn "Skipping verification (verification key unavailable)"
    else
      VERIFY_EXIT=0
      VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?
      fss_classify_verify_output "$VERIFY_OUTPUT"
      fss_verify_policy_decision \
        "$(fss_read_recorded_pre_fss_archive "$PRE_FSS_ARCHIVE_FILE")" \
        "$(fss_read_recorded_archive_list "$RECOVERY_ARCHIVES_FILE")"

      case "$FSS_VERDICT" in
      pass)
        if [ -n "$FSS_VERDICT_REASON" ]; then
          pass "Journal verification passed ($FSS_VERDICT_REASON)"
        else
          pass "Journal verification passed"
        fi
        ;;
      partial)
        warn "Journal verification PARTIAL [$FSS_VERDICT_TAGS] ($FSS_VERDICT_REASON)"
        echo "   Output: $VERIFY_OUTPUT"
        ;;
      fail)
        fail "Journal verification FAILED [$FSS_VERDICT_TAGS] ($FSS_VERDICT_REASON)"
        echo "   Output: $VERIFY_OUTPUT"
        ;;
      esac
      [ "$VERIFY_EXIT" -ne 0 ] && [ "$FSS_VERDICT" = "pass" ] &&
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
      RULES=$(auditctl -l 2>/dev/null || echo "no rules")
      if echo "$RULES" | grep -q "journal_fss_keys\|journal_sealed_logs"; then
        pass "FSS audit rules are configured"
      elif echo "$RULES" | grep -q "No rules"; then
        warn "No audit rules configured (auditd may not be enabled)"
      else
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
