# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Debugging tools for the logging server
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.logging;

  # Test script for verifying logging server configuration
  logging-server-tests = pkgs.writeShellApplication {
    name = "logging-server-tests";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      systemd
      iproute2
      gnugrep
      gawk
      openssl
      findutils
    ];
    text = ''
      set +e  # Don't exit on test failures

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      NC='\033[0m'

      echo "============================================"
      echo "  Ghaf Logging Server Test Suite"
      echo "  Admin-VM Verification"
      echo "============================================"
      echo ""

      PASSED=0
      FAILED=0
      WARNED=0

      pass() {
        echo -e "''${GREEN}[PASS]''${NC} $1"
        ((PASSED++))
      }

      fail() {
        echo -e "''${RED}[FAIL]''${NC} $1"
        ((FAILED++))
      }

      warn() {
        echo -e "''${YELLOW}[WARN]''${NC} $1"
        ((WARNED++))
      }

      info() {
        echo -e "''${BLUE}[INFO]''${NC} $1"
      }

      section() {
        echo ""
        echo "=========================================="
        echo "  $1"
        echo "=========================================="
      }

      # 1. Service Status
      section "Service Status"

      for service in alloy loki stunnel; do
        if systemctl is-active --quiet $service.service; then
          pass "$service service is running"
        else
          fail "$service service is not running"
          systemctl status $service.service --no-pager -l | head -20
        fi
      done

      # 2. Port Listeners
      section "Port Listeners"

      if ss -tln | grep -q ":${toString cfg.local.listenPort} "; then
        pass "Loki listening on port ${toString cfg.local.listenPort}"
      else
        fail "Loki not listening on port ${toString cfg.local.listenPort}"
      fi

      if ss -tln | grep -q ":${toString cfg.listener.backendPort} "; then
        pass "Alloy listening on port ${toString cfg.listener.backendPort}"
      else
        fail "Alloy not listening on port ${toString cfg.listener.backendPort}"
      fi

      if ss -tln | grep -q ":${toString cfg.listener.port} "; then
        pass "stunnel listening on port ${toString cfg.listener.port}"
      else
        fail "stunnel not listening on port ${toString cfg.listener.port}"
      fi

      # 3. Configuration Files
      section "Configuration Files"

      for file in "/etc/alloy/config.alloy:Alloy config" \
                  "${cfg.identifierFilePath}:Device identifier" \
                  "${cfg.tls.certFile}:TLS certificate" \
                  "${cfg.tls.keyFile}:TLS key"; do
        path=''${file%%:*}
        name=''${file##*:}
        if [ -f "$path" ]; then
          pass "$name exists"
        else
          fail "$name missing ($path)"
        fi
      done

      # 4. Alloy Configuration Validation
      section "Alloy Configuration"

      if grep -q "loki.source.api \"listener\"" /etc/alloy/config.alloy; then
        pass "Server config contains API listener"
      else
        fail "Server config missing API listener"
      fi

      if grep -q "loki.source.journal \"journal\"" /etc/alloy/config.alloy; then
        pass "Server config contains journal source"
      else
        fail "Server config missing journal source"
      fi

      ${lib.optionalString cfg.local.enable ''
        if grep -q "loki.write \"local\"" /etc/alloy/config.alloy; then
          pass "Server config contains local write"
        else
          fail "Server config missing local write"
        fi
      ''}

      ${lib.optionalString cfg.remote.enable ''
        if grep -q "loki.write \"external\"" /etc/alloy/config.alloy; then
          pass "Server config contains external write"
        else
          fail "Server config missing external write"
        fi
      ''}

      # 5. Loki API Health
      section "Loki API Health"

      READY=$(curl -s --max-time 5 http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/ready 2>/dev/null || echo "failed")
      if [ "$READY" = "ready" ]; then
        pass "Loki is ready"
      else
        fail "Loki not ready (got: $READY)"
      fi

      METRICS=$(curl -s --max-time 5 http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/metrics 2>/dev/null | grep -c "loki_" || echo "0")
      if [ "$METRICS" -gt 0 ]; then
        pass "Loki metrics available ($METRICS metrics)"
      else
        fail "Loki metrics not available"
      fi

      # 6. Ingestion Status
      section "Ingestion Status"

      INGESTED=$(curl -s --max-time 5 http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/metrics 2>/dev/null | \
        grep "loki_ingester_chunks_created_total" | awk '{print $2}' || echo "0")

      if [ "$INGESTED" != "0" ] && [ -n "$INGESTED" ]; then
        pass "Loki has ingested chunks (total: $INGESTED)"
      else
        warn "No chunks ingested yet (new deployment or no logs received)"
      fi

      ERRORS=$(curl -s --max-time 5 http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/metrics 2>/dev/null | \
        grep "loki_ingester_chunks_flush_failures_total" | awk '{print $2}' || echo "0")

      if [ "$ERRORS" = "0" ] || [ -z "$ERRORS" ]; then
        pass "No ingestion errors"
      else
        warn "Found $ERRORS ingestion errors"
      fi

      # 7. Query Test
      section "Log Query Test"

      NOW_SEC=$(date +%s)
      FIVE_MIN_AGO_SEC=$((NOW_SEC - 300))
      NOW="''${NOW_SEC}000000000"
      FIVE_MIN_AGO="''${FIVE_MIN_AGO_SEC}000000000"

      QUERY_URL="http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/loki/api/v1/query_range"

      RESULT=$(curl -s --max-time 10 -G "$QUERY_URL" \
        --data-urlencode "query={host=~\".+\"}" \
        --data-urlencode "start=$FIVE_MIN_AGO" \
        --data-urlencode "end=$NOW" \
        --data-urlencode "limit=10" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "failed")

      if [ "$RESULT" = "success" ]; then
        pass "Can query Loki successfully"

        HOSTS=$(curl -s --max-time 10 -G "$QUERY_URL" \
          --data-urlencode "query={host=~\".+\"}" \
          --data-urlencode "start=$FIVE_MIN_AGO" \
          --data-urlencode "end=$NOW" 2>/dev/null | \
          jq -r '.data.result[].stream.host' 2>/dev/null | sort -u | wc -l)

        if [ "$HOSTS" -gt 1 ]; then
          pass "Receiving logs from $HOSTS different hosts"
        elif [ "$HOSTS" -eq 1 ]; then
          warn "Only receiving logs from 1 host (admin-vm itself?)"
        else
          warn "No hosts found in recent logs"
        fi
      else
        fail "Cannot query Loki (got: $RESULT)"
      fi

      # 8. Categorization Check
      ${lib.optionalString cfg.categorization.enable ''
        section "Log Categorization"

        for category in security system; do
          COUNT=$(curl -s --max-time 10 -G "$QUERY_URL" \
            --data-urlencode "query={log_category=\"$category\"}" \
            --data-urlencode "start=$FIVE_MIN_AGO" \
            --data-urlencode "end=$NOW" 2>/dev/null | \
            jq -r '.data.result | length' 2>/dev/null || echo "0")

          if [ "$COUNT" != "0" ] && [ -n "$COUNT" ]; then
            pass "$category logs found ($COUNT streams)"
          else
            warn "No $category logs in last 5 minutes"
          fi
        done
      ''}

      # 9. Retention Configuration
      ${lib.optionalString cfg.local.retention.enable ''
        section "Retention Configuration"

        COMPACTOR_RUNNING=$(curl -s --max-time 5 http://${cfg.local.listenAddress}:${toString cfg.local.listenPort}/metrics 2>/dev/null | grep -c "loki_compactor_" || echo "0")
        if [ "$COMPACTOR_RUNNING" -gt 0 ]; then
          pass "Compactor is active"
        else
          warn "Compactor metrics not found (may not have run yet)"
        fi
      ''}

      # 10. Disk Usage
      section "Disk Usage"

      if [ -d "${cfg.local.dataDir}" ]; then
        DISK_USAGE=$(du -sh ${cfg.local.dataDir} 2>/dev/null | awk '{print $1}')
        info "Loki data directory: $DISK_USAGE"
      else
        fail "Loki data directory not found"
      fi

      WAL_PATHS=$(find /var/lib/alloy -type d -name "wal" 2>/dev/null || echo "")
      if [ -n "$WAL_PATHS" ]; then
        # shellcheck disable=SC2086
        WAL_SIZE=$(du -shc $WAL_PATHS 2>/dev/null | tail -1 | awk '{print $1}')
        info "Alloy WAL total: $WAL_SIZE"
      else
        warn "Alloy WAL directory not found"
      fi

      # 11. TLS Endpoint Test
      section "TLS Endpoint"

      if command -v openssl >/dev/null 2>&1; then
        STUNNEL_TEST=$(echo "Q" | timeout 5 openssl s_client -connect 127.0.0.1:${toString cfg.listener.port} -brief 2>&1 || echo "failed")
        if echo "$STUNNEL_TEST" | grep -q "SSL"; then
          pass "stunnel TLS endpoint responds"
        else
          warn "Could not verify stunnel TLS (may need client cert)"
        fi
      else
        info "openssl not available for TLS testing"
      fi

      # 12. Recent Service Logs
      section "Recent Service Logs"

      for service in alloy loki stunnel; do
        ERRORS=$(journalctl -u $service.service --since "5 minutes ago" 2>/dev/null | grep -c -i "error\|fail" || echo "0")
        if [ "$ERRORS" -eq 0 ]; then
          pass "$service: No recent errors"
        else
          warn "$service: Found $ERRORS error lines in last 5 minutes"
          journalctl -u $service.service --since "5 minutes ago" | grep -i "error\|fail" | tail -3 | sed 's/^/    /'
        fi
      done

      # Summary
      section "Summary"
      echo ""
      echo "Tests passed:  $PASSED"
      echo "Tests warned:  $WARNED"
      echo "Tests failed:  $FAILED"
      echo ""

      if [ $FAILED -eq 0 ] && [ $WARNED -eq 0 ]; then
        echo -e "''${GREEN}✓ All tests passed!''${NC}"
        exit 0
      elif [ $FAILED -eq 0 ]; then
        echo -e "''${YELLOW}⚠ Tests passed with warnings''${NC}"
        exit 0
      else
        echo -e "''${RED}✗ Some tests failed''${NC}"
        exit 1
      fi
    '';
  };
in
{
  config = lib.mkIf (cfg.server && cfg.debug.enable) {
    # Install debug tools
    environment.systemPackages = [ logging-server-tests ];
  };
}
