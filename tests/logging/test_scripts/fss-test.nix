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
# For a full evidence packet on warning/failure:
#   environment.systemPackages = [ pkgs.fss-debug ];
#   Then run: sudo fss-debug
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
    ${verifyClassifierLib}

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

    # Discover KEY_DIR: prefer fss-config pointer, fall back to hostname-based paths
    # The fss-config file is written by journal-fss-setup and contains the Nix-configured
    # key directory path, which is stable even when the runtime hostname differs (e.g. net-vm
    # with dynamic AD hostname).
    KEY_DIR=""
    FSS_CONFIG="/var/log/journal/$MACHINE_ID/fss-config"
    if [ -f "$FSS_CONFIG" ] && [ -s "$FSS_CONFIG" ]; then
      KEY_DIR=$(cat "$FSS_CONFIG")
      info "Discovered key directory from fss-config: $KEY_DIR"
    else
      # Fallback: try hostname-based paths (works for VMs without dynamic hostname)
      HOSTNAME=$(hostname)
      for CANDIDATE in \
        "/persist/common/journal-fss/$HOSTNAME" \
        "/etc/common/journal-fss/$HOSTNAME"; do
        if [ -d "$CANDIDATE" ]; then
          KEY_DIR="$CANDIDATE"
          info "Discovered key directory from hostname fallback: $KEY_DIR"
          break
        fi
      done
    fi

    # Test 3: Check verification key
    info "Test 3: Checking verification key..."
    FOUND_VERIFY_KEY=false
    VERIFY_KEY_PATH=""
    VERIFY_KEY_UNREADABLE=false

    if [ -n "$KEY_DIR" ] && [ -e "$KEY_DIR/verification-key" ]; then
      VERIFY_KEY_PATH="$KEY_DIR/verification-key"
      if [ -s "$VERIFY_KEY_PATH" ] && [ -r "$VERIFY_KEY_PATH" ]; then
        pass "Verification key exists at $VERIFY_KEY_PATH"
        FOUND_VERIFY_KEY=true
      elif [ -s "$VERIFY_KEY_PATH" ]; then
        VERIFY_KEY_UNREADABLE=true
        if [ "$(id -u)" -eq 0 ]; then
          fail "Verification key exists but is unreadable at $VERIFY_KEY_PATH"
        else
          warn "Verification key exists but is unreadable as $(id -un); rerun fss-test as root"
        fi
      else
        fail "Verification key exists but is empty at $VERIFY_KEY_PATH"
      fi
    fi

    if [ "$FOUND_VERIFY_KEY" = false ] && [ "$VERIFY_KEY_UNREADABLE" = false ]; then
      if [ -n "$KEY_DIR" ]; then
        fail "Verification key not found - journal verification cannot validate sealed logs"
      else
        warn "Verification key directory could not be discovered"
      fi
    fi

    # Test 4: Check initialized sentinel
    info "Test 4: Checking initialization sentinel..."
    FOUND_INIT=false

    if [ -n "$KEY_DIR" ] && [ -f "$KEY_DIR/initialized" ]; then
      pass "Initialization sentinel exists at $KEY_DIR/initialized"
      FOUND_INIT=true
    fi

    if [ "$FOUND_INIT" = false ]; then
      warn "Initialization sentinel not found"
    fi

    # Test 5: Run journal verification
    info "Test 5: Running journal verification..."

    VERIFY_KEY=""
    SHOULD_RUN_VERIFY=true
    if [ -n "$VERIFY_KEY_PATH" ] && [ -r "$VERIFY_KEY_PATH" ] && [ -s "$VERIFY_KEY_PATH" ]; then
      VERIFY_KEY=$(cat "$VERIFY_KEY_PATH")
      echo "   Using verification key from $VERIFY_KEY_PATH"
    elif [ "$VERIFY_KEY_UNREADABLE" = true ] && [ "$(id -u)" -ne 0 ]; then
      warn "Skipping sealed journal verification because the verification key is unreadable as $(id -un)"
      SHOULD_RUN_VERIFY=false
    elif [ -n "$KEY_DIR" ]; then
      fail "Skipping sealed journal verification because the verification key is unavailable"
      SHOULD_RUN_VERIFY=false
    else
      warn "Skipping sealed journal verification because the verification key directory is unknown"
      SHOULD_RUN_VERIFY=false
    fi

    if [ "$SHOULD_RUN_VERIFY" = true ]; then
      VERIFY_OUTPUT=""
      VERIFY_EXIT=0
      VERIFY_CMD="journalctl --verify --verify-key=$VERIFY_KEY"

      if VERIFY_OUTPUT=$($VERIFY_CMD 2>&1); then
        VERIFY_EXIT=0
      else
        VERIFY_EXIT=$?
      fi

      VERIFY_TAGS=$(fss_reason_tags_from_output "$VERIFY_OUTPUT")
      fss_classify_verify_output "$VERIFY_OUTPUT"
      VERIFY_TAGS=$(fss_classification_tags "$VERIFY_TAGS")

      if [ "$FSS_KEY_PARSE_ERROR" -eq 1 ] || [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]; then
        fail "Journal verification failed due to verification key defect [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
      elif [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]; then
        fail "Active system journal verification failed [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
      elif [ -n "$FSS_OTHER_FAILURES" ]; then
        fail "Journal verification found unclassified critical failures [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
      elif [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ] || [ -n "$FSS_USER_FAILURES" ]; then
        warn "Journal verification passed with archive/user warnings [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
      elif [ -n "$FSS_TEMP_FAILURES" ]; then
        pass "Journal verification passed (temporary journal files ignored)"
        echo "   Ignored temp failures: $FSS_TEMP_FAILURES"
      elif [ "$VERIFY_EXIT" -eq 0 ]; then
        pass "Journal verification passed"
      elif [ "$FSS_FILESYSTEM_RESTRICTION" -eq 1 ]; then
        warn "Verification encountered filesystem restrictions [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
      else
        warn "Verification returned exit code $VERIFY_EXIT without critical failures [$VERIFY_TAGS]"
        echo "   Output: $VERIFY_OUTPUT"
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
    elif systemctl cat journal-fss-verify.timer &>/dev/null; then
      if systemctl is-active --quiet journal-fss-verify.timer; then
        pass "journal-fss-verify.timer is active"
      else
        pass "journal-fss-verify.timer exists"
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

    if command -v fss-debug >/dev/null 2>&1 && { [ "$FAILED" -gt 0 ] || [ "$WARNED" -gt 0 ]; }; then
      echo "Detailed evidence capture: sudo fss-debug"
    fi

    if command -v fss-rootcause >/dev/null 2>&1 && { [ "$FAILED" -gt 0 ] || [ "$WARNED" -gt 0 ]; }; then
      echo "Checkpoint workflow: sudo fss-rootcause help"
      echo ""
    fi

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
