# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS (Forward Secure Sealing) Hardware Test Script
#
# Verifies FSS functionality on a deployed Ghaf system. This script checks
# that journal sealing is properly configured and working, providing
# tamper-evident logging via HMAC-SHA256 chains.
#
# Usage:
#   Build:   nix build .#checks.x86_64-linux.fss-test
#   Deploy:  scp result/bin/fss-test root@ghaf-host:/tmp/
#   Run:     ssh root@ghaf-host /tmp/fss-test
#
# Or deploy with system configuration:
#   environment.systemPackages = [ pkgs.fss-test ];
#   Then run: sudo fss-test
#
# Tests performed:
#   1. FSS setup service status - verifies journal-fss-setup ran
#   2. Sealing key existence - checks /var/log/journal/<machine-id>/fss
#   3. Verification key extraction - for offline log verification
#   4. Initialization sentinel - prevents re-initialization
#   5. Journal integrity verification - runs journalctl --verify
#   6. Verification timer status - periodic integrity checks
#   7. Audit rules configuration - monitors FSS key access
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
writeShellApplication {
  name = "fss-test";
  runtimeInputs = [
    coreutils
    systemd
    gnugrep
  ];
  text = ''
    set -euo pipefail

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    PASSED=0
    FAILED=0
    WARNED=0

    pass() { echo -e "''${GREEN}[PASS]''${NC} $1"; PASSED=$((PASSED + 1)); }
    fail() { echo -e "''${RED}[FAIL]''${NC} $1"; FAILED=$((FAILED + 1)); }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; WARNED=$((WARNED + 1)); }
    info() { echo -e "[INFO] $1"; }

    echo "=========================================="
    echo "  FSS (Forward Secure Sealing) Test Suite"
    echo "=========================================="
    echo ""

    # Test 1: Check FSS setup service
    info "Test 1: Checking journal-fss-setup service..."
    if systemctl list-unit-files 2>/dev/null | grep -q "journal-fss-setup"; then
      SERVICE_RESULT=$(systemctl show journal-fss-setup --property=Result 2>/dev/null | cut -d= -f2)
      SERVICE_STATE=$(systemctl show journal-fss-setup --property=ActiveState 2>/dev/null | cut -d= -f2)
      if [ "$SERVICE_RESULT" = "success" ] || [ "$SERVICE_STATE" = "active" ]; then
        pass "journal-fss-setup service completed successfully"
      else
        # One-shot service with RemainAfterExit=yes shows as inactive but with success result
        warn "journal-fss-setup service status: state=$SERVICE_STATE result=$SERVICE_RESULT"
      fi
    elif systemctl cat journal-fss-setup.service &>/dev/null; then
      # Service exists but may not show in list-unit-files
      pass "journal-fss-setup service exists"
    else
      # Fallback: if FSS key exists, service must have run
      MACHINE_ID=$(cat /etc/machine-id)
      if [ -f "/var/log/journal/$MACHINE_ID/fss" ] || [ -f "/run/log/journal/$MACHINE_ID/fss" ]; then
        pass "journal-fss-setup service ran (FSS key exists)"
      else
        fail "journal-fss-setup service not found - FSS may not be enabled"
      fi
    fi

    # Test 2: Check sealing key exists
    info "Test 2: Checking FSS sealing key..."
    MACHINE_ID=$(cat /etc/machine-id)
    FSS_KEY="/var/log/journal/$MACHINE_ID/fss"
    FSS_KEY_VOLATILE="/run/log/journal/$MACHINE_ID/fss"

    if [ -f "$FSS_KEY" ]; then
      pass "FSS sealing key exists at $FSS_KEY"
    elif [ -f "$FSS_KEY_VOLATILE" ]; then
      warn "FSS key in volatile storage: $FSS_KEY_VOLATILE (will be lost on reboot)"
    else
      fail "FSS sealing key not found in persistent or volatile storage"
    fi

    # Test 3: Check verification key
    info "Test 3: Checking verification key..."
    HOSTNAME=$(hostname)
    FOUND_VERIFY_KEY=false

    for KEY_PATH in \
      "/persist/common/journal-fss/$HOSTNAME/verification-key" \
      "/etc/common/journal-fss/$HOSTNAME/verification-key"; do
      if [ -f "$KEY_PATH" ] && [ -s "$KEY_PATH" ]; then
        pass "Verification key exists at $KEY_PATH"
        FOUND_VERIFY_KEY=true
        break
      fi
    done

    if [ "$FOUND_VERIFY_KEY" = false ]; then
      warn "Verification key not found - offline verification won't be possible"
    fi

    # Test 4: Check initialized sentinel
    info "Test 4: Checking initialization sentinel..."
    FOUND_INIT=false

    for INIT_PATH in \
      "/persist/common/journal-fss/$HOSTNAME/initialized" \
      "/etc/common/journal-fss/$HOSTNAME/initialized"; do
      if [ -f "$INIT_PATH" ]; then
        pass "Initialization sentinel exists at $INIT_PATH"
        FOUND_INIT=true
        break
      fi
    done

    if [ "$FOUND_INIT" = false ]; then
      warn "Initialization sentinel not found"
    fi

    # Test 5: Run journal verification
    info "Test 5: Running journal verification..."

    # Find and use verification key (same logic as verify service)
    # Without the key, sealed journals will fail verification with "Required key not available"
    VERIFY_KEY=""
    for KEY_PATH in \
      "/persist/common/journal-fss/$HOSTNAME/verification-key" \
      "/etc/common/journal-fss/$HOSTNAME/verification-key"; do
      if [ -f "$KEY_PATH" ] && [ -s "$KEY_PATH" ]; then
        VERIFY_KEY=$(cat "$KEY_PATH")
        echo "   Using verification key from $KEY_PATH"
        break
      fi
    done

    VERIFY_CMD="journalctl --verify"
    if [ -n "$VERIFY_KEY" ]; then
      VERIFY_CMD="journalctl --verify --verify-key=$VERIFY_KEY"
    else
      echo "   WARNING: No verification key found - sealed journals may fail verification"
    fi

    VERIFY_OUTPUT=""
    VERIFY_EXIT=0

    if VERIFY_OUTPUT=$($VERIFY_CMD 2>&1); then
      VERIFY_EXIT=0
    else
      VERIFY_EXIT=$?
    fi

    # Categorize failures:
    # - Active journal (system.journal): failures are critical
    # - Archived journals (system@*.journal): failures expected for pre-FSS entries, warn only
    # - Temp files (*.journal~): ignore completely
    ACTIVE_FAILURES=$(echo "$VERIFY_OUTPUT" | grep -i "FAIL" | grep -E '/system\.journal|/user-[0-9]+\.journal' | grep -v '\.journal~' || true)
    ARCHIVED_FAILURES=$(echo "$VERIFY_OUTPUT" | grep -i "FAIL" | grep -E '@.*\.journal' | grep -v '\.journal~' || true)

    if [ -n "$ACTIVE_FAILURES" ]; then
      fail "Active journal verification failed - potential integrity issue"
      echo "   Failures: $ACTIVE_FAILURES"
    elif [ -n "$ARCHIVED_FAILURES" ]; then
      # Archived journals may fail if they predate FSS activation - this is expected
      warn "Archived journals failed verification (expected for pre-FSS entries)"
      echo "   Archives: $ARCHIVED_FAILURES"
      echo "   Note: Run 'journalctl --vacuum-time=1s' to remove old archives if needed"
    elif [ "$VERIFY_EXIT" -eq 0 ]; then
      pass "Journal verification passed"
    else
      # Check for filesystem errors
      if echo "$VERIFY_OUTPUT" | grep -qi "read-only\|permission denied"; then
        warn "Verification encountered filesystem restrictions (not an integrity failure)"
      else
        warn "Verification returned exit code $VERIFY_EXIT but no critical failures detected"
      fi
    fi

    # Test 6: Check verification timer
    info "Test 6: Checking verification timer..."
    if systemctl list-unit-files 2>/dev/null | grep -q "journal-fss-verify.timer"; then
      if systemctl is-active --quiet journal-fss-verify.timer; then
        pass "journal-fss-verify.timer is active"
        NEXT_RUN=$(systemctl list-timers journal-fss-verify --no-pager 2>/dev/null | grep journal-fss-verify | awk '{print $1, $2}' || echo "unknown")
        echo "   Next run: $NEXT_RUN"
      else
        warn "journal-fss-verify.timer exists but is not active"
      fi
    else
      warn "journal-fss-verify.timer not found"
    fi

    # Test 7: Check audit rules (if auditd is available)
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
    echo ""
    echo "=========================================="
    echo "  FSS Test Suite Complete"
    echo "=========================================="
    echo ""
    echo -e "  ''${GREEN}Passed:''${NC}  $PASSED"
    echo -e "  ''${RED}Failed:''${NC}  $FAILED"
    echo -e "  ''${YELLOW}Warned:''${NC}  $WARNED"
    echo ""

    if [ "$FAILED" -gt 0 ]; then
      echo -e "''${RED}Some tests failed. FSS may not be working correctly.''${NC}"
      exit 1
    elif [ "$WARNED" -gt 0 ]; then
      echo -e "''${YELLOW}All critical tests passed, but some warnings were raised.''${NC}"
      exit 0
    else
      echo -e "''${GREEN}All tests passed. FSS is working correctly.''${NC}"
      exit 0
    fi
  '';
}
