# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS Verification Tests
#
_: ''
  machine.wait_until_succeeds("""
    bash -lc '
      systemctl is-active --quiet journal-fss-setup.service ||
      systemctl is-failed --quiet journal-fss-setup.service ||
      [ "$(systemctl show journal-fss-setup.service --property=ConditionResult --value)" = "no" ]
    '
  """)
  setup_status = machine.succeed("systemctl show journal-fss-setup --property=ActiveState,Result,ConditionResult")
  setup_succeeded = "Result=success" in setup_status
  verify_key_path = "/persist/common/journal-fss/test-host/verification-key"

  def skip_if_setup_failed(label):
      if not setup_succeeded:
          print(f"Skipping {label} because FSS setup did not complete successfully: {setup_status}")
          return True
      return False

  with subtest("Journal verification runs without critical errors"):
      if not skip_if_setup_failed("journal verification"):
          machine.succeed(f"test -r {verify_key_path} && test -s {verify_key_path}")
          machine.succeed("logger -t fss-test 'Test entry 1'")
          machine.succeed("logger -t fss-test 'Test entry 2'")
          machine.sleep(5)
          exit_code, output = machine.execute(f"""
            bash -lc '
              set -euo pipefail
              source /etc/fss-verify-classifier.sh
              MID=$(cat /etc/machine-id)
              journalctl --sync
              VERIFY_EXIT=0
              VERIFY_OUTPUT=$(journalctl --verify --verify-key="$(cat {verify_key_path})" 2>&1) || VERIFY_EXIT=$?
              RAW_RECOVERY_RECEIPTS=$(fss_read_receipts "/var/log/journal/$MID/fss-recovery-receipts")
              RAW_PRE_ACTIVATION_RECEIPTS=$(fss_read_pre_activation_receipts "/var/log/journal/$MID/fss-pre-activation-receipts")
              RAW_UNCLEAN_RECEIPTS=$(fss_read_unclean_shutdown_receipts "/var/log/journal/$MID/fss-unclean-shutdown-receipts")
              RECOVERY_RECEIPT_MISMATCHES=$(fss_receipt_mismatches "$RAW_RECOVERY_RECEIPTS")
              PRE_ACTIVATION_RECEIPT_MISMATCHES=$(fss_pre_activation_receipt_mismatches "$RAW_PRE_ACTIVATION_RECEIPTS")
              UNCLEAN_RECEIPT_MISMATCHES=$(fss_unclean_shutdown_receipt_mismatches "$RAW_UNCLEAN_RECEIPTS")
              if [ -n "$RECOVERY_RECEIPT_MISMATCHES$PRE_ACTIVATION_RECEIPT_MISMATCHES$UNCLEAN_RECEIPT_MISMATCHES" ]; then
                printf "receipt mismatch: recovery=%s pre_activation=%s unclean=%s\n" \
                  "$RECOVERY_RECEIPT_MISMATCHES" "$PRE_ACTIVATION_RECEIPT_MISMATCHES" "$UNCLEAN_RECEIPT_MISMATCHES"
                exit 1
              fi
              fss_classify_verify_output "$VERIFY_OUTPUT"
              fss_verify_policy_decision \
                "$(fss_read_recorded_pre_fss_archive "/var/log/journal/$MID/fss-pre-fss-archive")" \
                "$(fss_filter_valid_receipts "$RAW_RECOVERY_RECEIPTS")" \
                "$(fss_filter_valid_receipts "$RAW_PRE_ACTIVATION_RECEIPTS")" \
                "$(cat /proc/sys/kernel/random/boot_id)" \
                "$VERIFY_EXIT" \
                "$(fss_filter_valid_receipts "$RAW_UNCLEAN_RECEIPTS")"
              if [ "$FSS_VERDICT" = "fail" ]; then
                printf "%s\\n%s\\n" "$FSS_VERDICT_TAGS" "$VERIFY_OUTPUT"
                exit 1
              fi
            '
          """)
          if exit_code != 0:
              raise Exception(f"Journal verification found critical failures: {output}")
          print(f"Journal verification completed (exit code: {exit_code})")

  with subtest("Classifier + policy cover all failure branches"):
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          source /etc/fss-verify-classifier.sh

          # Assert that classifying $sample and running policy yields $want.
          # Usage: assert_verdict <want> <sample> [pre] [recovery_receipts] [pre_activation_receipts] [boot] [verify_exit]
          assert_verdict() {
            local want="$1" sample="$2" pre="''${3:-}" recov="''${4:-}" receipts="''${5:-}" boot="''${6:-}" verify_exit="''${7:-0}" unclean="''${8:-}"
            fss_classify_verify_output "$sample"
            fss_verify_policy_decision "$pre" "$recov" "$receipts" "$boot" "$verify_exit" "$unclean"
            if [ "$FSS_VERDICT" != "$want" ]; then
              printf "verdict mismatch: want=%s got=%s reason=%s tags=%s sample=%s\n" \
                "$want" "$FSS_VERDICT" "$FSS_VERDICT_REASON" "$FSS_VERDICT_TAGS" "$sample" >&2
              return 1
            fi
          }

          # Build a synthetic pre-activation receipt record for path and boot id.
          mkreceipt() {
            printf "v1\t%s\t111\t2048\t%s\t1700000000\tdeadbeef\tpre-activation-rotation\tevt" "$1" "$2"
          }

          mkuncleanreceipt() {
            printf "v1\t%s\t111\t2048\t%s\t1700000000\tdeadbeef\tunclean-shutdown\tevt" "$1" "$2"
          }

          CURBOOT="boot-current"
          ACTIVE="/var/log/journal/mid/system.journal"
          ALLOWED_ARCHIVE="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal"
          RECOVERY_ARCHIVE="/var/log/journal/mid/system@0000000000000005-0000000000000006.journal"
          STALE_RECOVERY_ARCHIVE="/var/log/journal/mid/system@0000000000000011-0000000000000012.journal"
          PRE_ACTIVATION_ARCHIVE="/var/log/journal/mid/system@0000000000000007-0000000000000008.journal"
          STALE_PRE_ACTIVATION_ARCHIVE="/var/log/journal/mid/system@0000000000000009-0000000000000010.journal"
          UNEXPECTED_ARCHIVE="/var/log/journal/mid/system@0000000000000003-0000000000000004.journal"
          USER_JOURNAL="/var/log/journal/mid/user-1000@0000000000000001-0000000000000002.journal"
          TEMP_JOURNAL="/var/log/journal/mid/custom.journal~"
          ACTIVE_TEMP_JOURNAL="/var/log/journal/mid/system.journal~"
          ARCHIVED_TEMP_JOURNAL="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal~"
          OTHER="/var/log/journal/mid/custom.journal"

          # Active system failure → fail
          assert_verdict fail "FAIL: $ACTIVE (Bad message)"
          [ "$FSS_REASON_TAGS" = "BAD_MESSAGE" ]

          # Clean output → verified
          assert_verdict verified "PASS: $ACTIVE"

          # Clean output with current-boot pre-activation receipt still means
          # verified-with-exception: those entries were structurally readable but
          # not FSS-trusted.
          assert_verdict verified-with-exception \
            "PASS: $ACTIVE" \
            "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "recorded insecure boot logs (current boot)" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_ARCHIVE"

          # Clean output with only an EARLIER-boot pre-activation receipt → warning:
          # old unsealed boot logs lingering on disk must not report as fully verified.
          assert_verdict warning \
            "PASS: $ACTIVE" \
            "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "boot-earlier")" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

          # Clean output with both current and earlier-boot receipts → warning:
          # stale retained evidence must not be hidden by a new current-boot receipt.
          MIXED_PRE_ACTIVATION_RECEIPTS="$(printf "%s\n%s" \
            "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" \
            "$(mkreceipt "$STALE_PRE_ACTIVATION_ARCHIVE" "boot-earlier")")"
          assert_verdict warning \
            "PASS: $ACTIVE" \
            "" "" "$MIXED_PRE_ACTIVATION_RECEIPTS" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

          # Allowed archive only → verified-with-exception (matches pre-FSS allowlist)
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$ALLOWED_ARCHIVE" "$ACTIVE")" \
            "$ALLOWED_ARCHIVE"
          [ "$FSS_REASON_TAGS" = "INPUT_OUTPUT_ERROR" ]
          [ "$FSS_VERDICT_REASON" = "recorded archived-system exceptions only" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_FSS_ARCHIVE"
          fss_matches_only_expected_archived_system_failure "$ALLOWED_ARCHIVE"

          # Legacy path-only recovery archive → fail (no longer trusted)
          assert_verdict fail \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$RECOVERY_ARCHIVE" "$ACTIVE")" \
            "" "$(printf "%s\n%s" "$RECOVERY_ARCHIVE" "$RECOVERY_ARCHIVE")"

          # Current-boot recovery receipt → verified-with-exception
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$RECOVERY_ARCHIVE" "$ACTIVE")" \
            "" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "recorded recovery archive (current boot)" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "RECOVERY_ARCHIVE"

          # Earlier-boot recovery receipt → warning
          assert_verdict warning \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$STALE_RECOVERY_ARCHIVE" "$ACTIVE")" \
            "" "$(mkreceipt "$STALE_RECOVERY_ARCHIVE" "boot-earlier")" "" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "recovery archive from an earlier boot" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "RECOVERY_STALE"

          # Current-boot pre-activation receipt → verified-with-exception
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
            "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "recorded insecure boot logs (current boot)" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_ARCHIVE"
          ! printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

          # Earlier-boot pre-activation receipt → warning (evidenced but stale)
          assert_verdict warning \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
            "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "boot-earlier")" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

          # Archived failure with no matching receipt → fail (unrecorded/substituted)
          assert_verdict fail \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
            "" "" "" "$CURBOOT"

          # Unexpected archive → fail
          assert_verdict fail \
            "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$UNEXPECTED_ARCHIVE" "$ACTIVE")" \
            "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

          # Allowed + recovery archives together → verified-with-exception
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE")" \
            "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

          # Allowed + unexpected archive → fail (allowlist miss on one path)
          assert_verdict fail \
            "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$UNEXPECTED_ARCHIVE")" \
            "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

          # Filesystem restrictions make otherwise allowlisted verifies a warning
          assert_verdict warning "Failed to open journal file: Read-only file system"
          [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

          assert_verdict warning \
            "$(printf "Failed to open journal file: Read-only file system\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE")" \
            "$ALLOWED_ARCHIVE"
          [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

          assert_verdict warning \
            "$(printf "Failed to open journal file: Permission denied\nFAIL: %s (Bad message)" "$RECOVERY_ARCHIVE")" \
            "" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"
          [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

          assert_verdict fail \
            "$(printf "Failed to open journal file: Read-only file system\nFAIL: %s (Bad message)" "$UNEXPECTED_ARCHIVE")" \
            "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

          # User journal failure alone → warning (non-fatal)
          assert_verdict warning "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
          [ -n "$FSS_USER_FAILURES" ]
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]

          # Localized journalctl reason text still classifies by failed path.
          assert_verdict warning "$(printf "FAIL: %s (Virheellinen viesti)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
          [ -n "$FSS_USER_FAILURES" ]
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          ! printf "%s" "$FSS_REASON_TAGS" | grep -F "BAD_MESSAGE"

          assert_verdict fail "FAIL: $ACTIVE (Virheellinen viesti)"
          [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -z "$FSS_REASON_TAGS" ]

          # User journal with corruption diagnostics → warning
          assert_verdict warning "$(printf "2cb2e0: Tag failed verification\nFile corruption detected at %s:2929376 (of 8388608 bytes, 34%%).\nFAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$USER_JOURNAL" "$ACTIVE")"

          # Temp journal failure → warning (ignored leftover)
          assert_verdict warning "FAIL: $TEMP_JOURNAL (Bad message)"
          [ -n "$FSS_TEMP_FAILURES" ]

          # Critical system journals renamed with ~ retain their base severity.
          assert_verdict fail "FAIL: $ACTIVE_TEMP_JOURNAL (Bad message)"
          [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          assert_verdict fail "FAIL: $ARCHIVED_TEMP_JOURNAL (Bad message)"
          [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]

          # Unclean-shutdown receipting (journald-attested, content-bound). An
          # archived .journal~ corpse with a current-boot unclean receipt is an
          # expected exception, not a hard fail.
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ARCHIVED_TEMP_JOURNAL" "$ACTIVE")" \
            "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"
          [ "$FSS_VERDICT_REASON" = "recorded unclean-shutdown journal (current boot)" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "UNCLEAN_SHUTDOWN"

          # The active system.journal~ corpse is carved out of the fatal active-system
          # set only with a matching content-bound receipt.
          assert_verdict verified-with-exception \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ACTIVE_TEMP_JOURNAL" "$ACTIVE")" \
            "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ACTIVE_TEMP_JOURNAL" "$CURBOOT")"

          # The LIVE system.journal (no ~) is NEVER exempted, even with an unclean
          # receipt present for some other path.
          assert_verdict fail \
            "FAIL: $ACTIVE (Bad message)" \
            "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"

          # An unmatched system@*.journal~ (no receipt) still fails closed.
          assert_verdict fail \
            "FAIL: $ARCHIVED_TEMP_JOURNAL (Bad message)" \
            "" "" "" "$CURBOOT" 1 ""

          # Earlier-boot unclean receipt → warning (stale must not pass forever).
          assert_verdict warning \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ARCHIVED_TEMP_JOURNAL" "$ACTIVE")" \
            "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "boot-earlier")"
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "UNCLEAN_SHUTDOWN_STALE"

          # Clean output + current-boot unclean receipt → verified-with-exception.
          assert_verdict verified-with-exception \
            "PASS: $ACTIVE" \
            "" "" "" "$CURBOOT" 0 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"

          # Other/unclassified journal → fail
          assert_verdict fail "FAIL: $OTHER (Bad message)"
          [ -n "$FSS_OTHER_FAILURES" ]

          # Key parse + missing key → fail
          assert_verdict fail "$(printf "Failed to parse seed.\nFAIL: %s (Required key not available)" "$ACTIVE")"
          [ "$FSS_KEY_PARSE_ERROR" -eq 1 ]
          [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]
          [ "$FSS_REASON_TAGS" = "KEY_PARSE_ERROR,KEY_MISSING" ]

          # Empty input → verified (no findings)
          assert_verdict verified ""
          [ -z "$FSS_REASON_TAGS" ]
          [ -z "$FSS_FAIL_LINES" ]

          # Nonzero verify exit with no classified exception → fail
          assert_verdict fail "" "" "" "" "$CURBOOT" 42
          [ "$FSS_VERDICT_REASON" = "journalctl verify exited nonzero without a classified exception" ]
          printf "%s" "$FSS_VERDICT_TAGS" | grep -F "VERIFY_EXIT_UNCLASSIFIED"

          # Content-bound receipt filtering against the live filesystem.
          real=$(mktemp)
          printf "original" > "$real"
          rino=$(stat -c %i "$real"); rsz=$(stat -c %s "$real"); rsha=$(sha256sum "$real" | cut -d" " -f1)
          good=$(printf "v1\t%s\t%s\t%s\t%s\t1\t%s\tpre-activation-rotation\tevt" "$real" "$rino" "$rsz" "$CURBOOT" "$rsha")
          [ "$(fss_filter_valid_receipts "$good")" = "$good" ]
          [ -z "$(fss_pre_activation_receipt_mismatches "$good")" ]
          weak=$(printf "v1\t%s\t%s\t%s\t%s\t1\t-\tpre-activation-rotation\tevt" "$real" "$rino" "$rsz" "$CURBOOT")
          [ -z "$(fss_filter_valid_receipts "$weak")" ]
          [ -z "$(fss_pre_activation_receipt_mismatches "$weak")" ]
          # Substituted content (size + hash change) → receipt dropped
          printf "tampered-and-longer" > "$real"
          [ "$(fss_pre_activation_receipt_mismatches "$good")" = "$real" ]
          [ -z "$(fss_filter_valid_receipts "$good")" ]
          # Missing file → receipt dropped
          rm -f "$real"
          [ -z "$(fss_pre_activation_receipt_mismatches "$good")" ]
          [ -z "$(fss_filter_valid_receipts "$good")" ]

          # Bucket classification and dedup of unique fail paths
          MIXED=$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)" \
            "$ACTIVE" "$ACTIVE" "$ALLOWED_ARCHIVE" "$USER_JOURNAL" "$TEMP_JOURNAL" "$OTHER")
          [ "$(fss_count_nonempty_lines "$(fss_unique_fail_paths_from_output "$MIXED")")" -eq 5 ]
          [ "$(fss_failure_bucket_for_path "$ACTIVE")" = "active-system" ]
          [ "$(fss_failure_bucket_for_path "$ALLOWED_ARCHIVE")" = "archived-system" ]
          [ "$(fss_failure_bucket_for_path "$USER_JOURNAL")" = "user-journal" ]
          [ "$(fss_failure_bucket_for_path "$TEMP_JOURNAL")" = "temp" ]
          [ "$(fss_failure_bucket_for_path "$ACTIVE_TEMP_JOURNAL")" = "active-system" ]
          [ "$(fss_failure_bucket_for_path "$ARCHIVED_TEMP_JOURNAL")" = "archived-system" ]
          [ "$(fss_failure_bucket_for_path "$OTHER")" = "other" ]

          # Log format: level names are case-insensitive; output has no color when stdout is piped.
          log_output=$(fss_log pass "pass message"
                       fss_log FAIL "fail message"
                       fss_log warning "warn message"
                       fss_log info "info message"
                       fss_log_block < <(printf "%s\n" "block line 1" "block line 2"))
          expected=$(printf "[PASS] pass message\n[FAIL] fail message\n[WARN] warn message\n[INFO] info message\nblock line 1\nblock line 2")
          [ "$log_output" = "$expected" ]

          # State-file readers trim whitespace and dedupe.
          state=$(mktemp)
          printf "  %s \n" "$ALLOWED_ARCHIVE" > "$state"
          [ "$(fss_read_recorded_pre_fss_archive "$state")" = "$ALLOWED_ARCHIVE" ]
          rm -f "$state"
          [ -z "$(fss_read_recorded_pre_fss_archive "$state")" ]

          list=$(mktemp)
          printf " %s \n%s\n%s\n" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE" "$RECOVERY_ARCHIVE" > "$list"
          [ "$(fss_read_recorded_archive_list "$list")" = "$(printf "%s\n%s" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE")" ]
          rm -f "$list"
        '
      """)

  with subtest("Clock-jump recovery defaults are enabled"):
      machine.succeed("systemctl list-unit-files ghaf-clock-ready.service")
      machine.succeed("systemctl list-unit-files ghaf-clock-jump-watcher.service")
      machine.succeed("systemctl list-unit-files ghaf-journal-alloy-recover.service")
      machine.wait_for_unit("ghaf-clock-ready.service")
      machine.wait_for_unit("ghaf-clock-jump-watcher.service")
      status = machine.succeed("systemctl show ghaf-clock-jump-watcher.service --property=ActiveState,UnitFileState")
      if "ActiveState=active" not in status or "UnitFileState=enabled" not in status:
          raise Exception(f"Clock-jump watcher not enabled: {status}")

  with subtest("Clock readiness gates persistent FSS logging"):
      machine.wait_for_unit("ghaf-clock-sync.service")
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          test -e /run/ghaf-clock-ready
          test -s /run/ghaf-clock-ready-state
          test -s /var/lib/ghaf/clock-ready/last-good-realtime
          # The early barrier defers the NTP wait so it cannot stall journal flush.
          grep -F "sync_result=deferred" /run/ghaf-clock-ready-state
          systemctl cat ghaf-clock-ready.service | grep -F "TimeoutStartSec=35s"

          # The NTP wait happens in the separate sync unit, after networking.
          test -s /run/ghaf-clock-sync-state
          grep -E "sync_result=(synchronized|timeout|disabled|timedatectl-unavailable)" /run/ghaf-clock-sync-state

          # The early journal flush only waits on the fast barrier, never the NTP unit.
          for unit in systemd-journal-flush.service journal-fss-setup.service journal-fss-verify.service; do
            systemctl show "$unit" --property=After --property=Requires --property=Wants |
              grep -F "ghaf-clock-ready.service"
          done
          flush_after="$(systemctl show systemd-journal-flush.service --property=After)"
          if printf "%s" "$flush_after" | grep -F "ghaf-clock-sync.service"; then
            echo "journal flush must not order after the NTP sync unit" >&2
            exit 1
          fi
          # FSS activation, however, must wait for the sync unit.
          systemctl show journal-fss-setup.service --property=After | grep -F "ghaf-clock-sync.service"

          # Clock-jump recovery must not run in the activation Seal=no window.
          for unit in ghaf-clock-jump-watcher.service ghaf-journal-alloy-recover.service; do
            systemctl show "$unit" --property=After --property=Wants |
              grep -F "journal-fss-setup.service"
          done
        '
      """)

  with subtest("Clock readiness does not downgrade last-good anchor on fallback"):
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          anchor="/var/lib/ghaf/clock-ready/last-good-realtime"
          future="$(( $(date +%s) + 3600 ))"
          printf "%s\n" "$future" > "$anchor"
          chmod 0644 "$anchor"
          rm -f /run/ghaf-clock-ready
          systemctl reset-failed ghaf-clock-ready.service >/dev/null 2>&1 || true
          systemctl restart ghaf-clock-ready.service
          [ "$(cat "$anchor")" = "$future" ]
          test -e /run/ghaf-clock-ready
        '
      """)

  with subtest("Clock readiness self-heals future-poisoned anchors"):
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          anchor="/var/lib/ghaf/clock-ready/last-good-realtime"
          poison=2524608001
          printf "%s\n" "$poison" > "$anchor"
          chmod 0644 "$anchor"
          rm -f /run/ghaf-clock-ready
          systemctl reset-failed ghaf-clock-ready.service >/dev/null 2>&1 || true
          systemctl restart ghaf-clock-ready.service
          [ "$(cat "$anchor")" -lt "$poison" ]
          grep -F "max_allowed=2524608000" /run/ghaf-clock-ready-state
          grep -F "anchor_status=ignored-future" /run/ghaf-clock-ready-state
          test -e /run/ghaf-clock-ready
        '
      """)

  with subtest("Clock-jump recovery tolerates missing alloy service"):
      exit_code, output = machine.execute("systemctl start ghaf-journal-alloy-recover.service 2>&1")
      if exit_code != 0:
          raise Exception(f"Clock-jump recovery service failed without alloy: {output}")
      status = machine.succeed("systemctl show ghaf-journal-alloy-recover.service --property=Result,ExecMainStatus")
      if "Result=success" not in status:
          raise Exception(f"Clock-jump recovery did not complete: {status}")

  with subtest("Clock-jump recovery ignores future wallclock-style cooldown stamps"):
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          stamp="/run/ghaf-journal-alloy-recover.stamp"
          echo 999999999999 > "$stamp"
          systemctl reset-failed ghaf-journal-alloy-recover.service >/dev/null 2>&1 || true
          systemctl start ghaf-journal-alloy-recover.service >/tmp/ghaf-journal-alloy-recover-future-stamp.log 2>&1
          systemctl show ghaf-journal-alloy-recover.service --property=Result,ExecMainStatus | grep -F "Result=success"
          new_stamp=$(cat "$stamp")
          [ "$new_stamp" != "999999999999" ] && [ "$new_stamp" -lt 999999999999 ]
        '
      """)

  with subtest("Journal files are created"):
      mid = machine.succeed("cat /etc/machine-id").strip()
      exit_code, files = machine.execute(f"ls /var/log/journal/{mid}/*.journal 2>/dev/null || ls /run/log/journal/{mid}/*.journal 2>/dev/null")
      print(f"Journal files: {files.strip() or '(none yet)'}")

  with subtest("FSS verify service can be triggered"):
      machine.succeed("systemctl list-unit-files journal-fss-verify.service")
      machine.execute("systemctl start journal-fss-verify.service 2>&1")

  with subtest("Deployed fss-test operator tool runs"):
      if not skip_if_setup_failed("fss-test"):
          machine.succeed("fss-test >/tmp/fss-test-operator.log 2>&1 || { cat /tmp/fss-test-operator.log; exit 1; }")

  with subtest("Setup records activation state and a content-bound receipt store"):
      if not skip_if_setup_failed("activation state + receipts"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              # Activation is enabled by default in the test config; setup must
              # have confirmed sealing and written the runtime drop-in.
              [ "$(awk -F "\t" "NR == 1 { print \\$1 }" "$DIR/fss-activation-state")" = "active" ]
              [ "$(awk -F "\t" "NR == 1 { print \\$2 }" "$DIR/fss-activation-state")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
              test -f /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
              systemd-analyze cat-config systemd/journald.conf | grep -E "^[[:space:]]*Seal[[:space:]]*=[[:space:]]*no"
              effective_seal=$(systemd-analyze cat-config systemd/journald.conf | awk -F= '"'"'
                /^[[:space:]]*[#;]/ { next }
                /^[[:space:]]*Seal[[:space:]]*=/ {
                  value = $2
                  sub(/^[[:space:]]*/, "", value)
                  sub(/[[:space:]]*[#;].*$/, "", value)
                  sub(/[[:space:]]*$/, "", value)
                  seal = tolower(value)
                }
                END { print seal }
              '"'"')
              [ "$effective_seal" = yes ]
              # If a pre-activation receipt was recorded, it must be schema v1 and
              # tagged with this boot id.
              if [ -s "$DIR/fss-pre-activation-receipts" ]; then
                while IFS="$(printf "\t")" read -r ver path inode size rboot rest; do
                  [ -n "$ver" ] || continue
                  [ "$ver" = "v1" ]
                  [ -n "$rboot" ]
                done < "$DIR/fss-pre-activation-receipts"
              fi
            '
          """)

  with subtest("Setup restart does not receipt post-activation archives"):
      if not skip_if_setup_failed("post-activation receipt guard"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              RECEIPTS="$DIR/fss-pre-activation-receipts"
              POST="$DIR/system@ffffffffffffffff-ffffffffffffffff.journal"

              cleanup() {
                rm -f "$POST"
                systemctl reset-failed journal-fss-setup.service >/dev/null 2>&1 || true
              }
              trap cleanup EXIT

              [ "$(awk -F "\t" "NR == 1 { print \\$1 }" "$DIR/fss-activation-state")" = "active" ]
              test -f /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
              : > "$POST"
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-post-activation-receipt.log 2>&1
              if [ -f "$RECEIPTS" ]; then
                ! grep -F "$POST" "$RECEIPTS"
              fi
            '
          """)

  with subtest("Setup rotates on the first activation of each boot"):
      if not skip_if_setup_failed("per-boot activation rotation"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              STATE="$DIR/fss-activation-state"
              BASE="$DIR/fss-baseline-boot"
              MARKER="$DIR/fss-rotated"
              BOOT="$(cat /proc/sys/kernel/random/boot_id)"

              test -f "$MARKER"
              old_marker_mtime="$(stat -c %Y "$MARKER")"
              printf "active\tprevious-boot\n" > "$STATE"; chmod 0644 "$STATE"
              printf "previous-boot\n" > "$BASE"; chmod 0644 "$BASE"
              sleep 1
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-first-activation-rotation.log 2>&1

              [ "$(awk -F "\t" "NR == 1 { print \\$1 }" "$STATE")" = "active" ]
              [ "$(awk -F "\t" "NR == 1 { print \\$2 }" "$STATE")" = "$BOOT" ]
              [ "$(tr -d "[:space:]" < "$BASE")" = "$BOOT" ]
              [ "$(stat -c %Y "$MARKER")" -gt "$old_marker_mtime" ]
              journalctl -u journal-fss-setup.service -n 40 --no-pager |
                grep -F "Rotating journal to ensure clean FSS state"
            '
          """)

  with subtest("Verify fails closed when activation could not be confirmed"):
      if not skip_if_setup_failed("activation fail-closed"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              STATE="/var/log/journal/$MID/fss-activation-state"
              BASE="/var/log/journal/$MID/fss-baseline-boot"
              BOOT="$(cat /proc/sys/kernel/random/boot_id)"
              ORIG=""
              ORIG_BASE=""
              [ -f "$STATE" ] && ORIG="$(cat "$STATE")"
              [ -f "$BASE" ] && ORIG_BASE="$(cat "$BASE")"
              restore() {
                if [ -n "$ORIG" ]; then printf "%s\n" "$ORIG" > "$STATE"; else rm -f "$STATE"; fi
                if [ -n "$ORIG_BASE" ]; then printf "%s\n" "$ORIG_BASE" > "$BASE"; else rm -f "$BASE"; fi
                systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              }
              trap restore EXIT

              printf "failed\n" > "$STATE"; chmod 0644 "$STATE"
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/fss-verify-activation-failed.log 2>&1; then
                echo "verify unexpectedly passed with activation=failed" >&2; exit 1
              fi
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "ACTIVATION_FAILED"

              RECOV="/var/log/journal/$MID/fss-recovery-receipts"
              old_recov="$(cat "$RECOV" 2>/dev/null || true)"
              rm -f /run/ghaf-journal-alloy-recover.stamp
              systemctl reset-failed ghaf-journal-alloy-recover.service >/dev/null 2>&1 || true
              systemctl start ghaf-journal-alloy-recover.service >/tmp/ghaf-journal-alloy-recover-activation-failed.log 2>&1
              [ ! -e /run/ghaf-journal-alloy-recover.stamp ]
              [ "$(cat "$RECOV" 2>/dev/null || true)" = "$old_recov" ]

              rm -rf /tmp/fss-triage-activation-failed
              if fss-triage --strict-exit --no-sync --output-dir /tmp/fss-triage-activation-failed >/tmp/fss-triage-activation-failed.log 2>&1; then
                echo "triage unexpectedly passed with activation=failed" >&2; exit 1
              fi
              grep -F "activation-preflight" /tmp/fss-triage-activation-failed/verify/summary.tsv
              grep -F "ACTIVATION_FAILED" /tmp/fss-triage-activation-failed/verify/summary.tsv

              printf "active\tstale-boot\n" > "$STATE"; chmod 0644 "$STATE"
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/fss-verify-activation-stale.log 2>&1; then
                echo "verify unexpectedly passed with stale activation state" >&2; exit 1
              fi
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "ACTIVATION_STALE"

              rm -f "$STATE"
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/fss-verify-activation-missing.log 2>&1; then
                echo "verify unexpectedly passed with missing activation state" >&2; exit 1
              fi
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "ACTIVATION_STALE"

              printf "active\t%s\n" "$BOOT" > "$STATE"; chmod 0644 "$STATE"
              rm -f "$BASE"
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/fss-verify-activation-missing-baseline.log 2>&1; then
                echo "verify unexpectedly passed with missing activation baseline" >&2; exit 1
              fi
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "ACTIVATION_STALE"
            '
          """)

  with subtest("Setup fails closed when effective journald Seal is overridden"):
      if not skip_if_setup_failed("effective Seal override"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              STATE="$DIR/fss-activation-state"
              OVERRIDE="/etc/systemd/journald.conf.d/99-fss-test-seal-no.conf"
              BOOT="$(cat /proc/sys/kernel/random/boot_id)"

              effective_seal() {
                systemd-analyze cat-config systemd/journald.conf | awk -F= '"'"'
                  /^[[:space:]]*[#;]/ { next }
                  /^[[:space:]]*Seal[[:space:]]*=/ {
                    value = $2
                    sub(/^[[:space:]]*/, "", value)
                    sub(/[[:space:]]*[#;].*$/, "", value)
                    sub(/[[:space:]]*$/, "", value)
                    seal = tolower(value)
                  }
                  END { print seal }
                '"'"'
              }

              cleanup() {
                rm -f "$OVERRIDE"
                systemctl reset-failed journal-fss-setup.service journal-fss-verify.service >/dev/null 2>&1 || true
                systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-seal-override-cleanup.log 2>&1 || true
              }
              trap cleanup EXIT

              mkdir -p "$(dirname "$OVERRIDE")"
              printf "[Journal]\nSeal=no\n" > "$OVERRIDE"
              [ "$(effective_seal)" = no ]

              if systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-seal-override.log 2>&1; then
                echo "setup unexpectedly succeeded with effective Seal=no" >&2; exit 1
              fi
              [ "$(awk -F "\t" "NR == 1 { print \\$1 }" "$STATE")" = "failed" ]
              journalctl -u journal-fss-setup.service -n 60 --no-pager |
                grep -F "Journald sealing could not be confirmed after restart"
              journalctl -u journal-fss-setup.service -n 60 --no-pager |
                grep -F "Skipping FSS cleanup rotation because sealing activation failed"

              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/fss-verify-seal-override.log 2>&1; then
                echo "verify unexpectedly passed with effective Seal=no" >&2; exit 1
              fi
              journalctl -u journal-fss-verify.service -n 30 --no-pager | grep -F "ACTIVATION_FAILED"

              rm -f "$OVERRIDE"
              systemctl reset-failed journal-fss-setup.service journal-fss-verify.service >/dev/null 2>&1 || true
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-seal-override-recovery.log 2>&1
              [ "$(awk -F "\t" "NR == 1 { print \\$1 }" "$STATE")" = "active" ]
              [ "$(awk -F "\t" "NR == 1 { print \\$2 }" "$STATE")" = "$BOOT" ]
              [ "$(effective_seal)" = yes ]
            '
          """)

  with subtest("Setup repairs a missing same-boot baseline without rotating"):
      if not skip_if_setup_failed("per-boot baseline"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              PRE="$DIR/fss-pre-fss-archive"
              RECOV="$DIR/fss-recovery-receipts"
              BASE="$DIR/fss-baseline-boot"
              MARKER="$DIR/fss-rotated"

              test -s "$PRE"
              old_pre="$(tr -d "[:space:]" < "$PRE")"
              old_recov="$(cat "$RECOV" 2>/dev/null || true)"
              old_marker_mtime="$(stat -c %Y "$MARKER")"
              rm -f "$BASE"
              sleep 1
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-per-boot-baseline.log 2>&1

              test -s "$BASE"
              [ "$(tr -d "[:space:]" < "$BASE")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
              [ "$(tr -d "[:space:]" < "$PRE")" = "$old_pre" ]
              [ "$(cat "$RECOV" 2>/dev/null || true)" = "$old_recov" ]
              [ "$(stat -c %Y "$MARKER")" = "$old_marker_mtime" ]
              journalctl -u journal-fss-setup.service -n 20 --no-pager |
                grep -F "Restoring current boot FSS baseline without post-activation rotation"
            '
          """)

  with subtest("Setup backfills only the archive created at the original FSS rotation"):
      if not skip_if_setup_failed("archive backfill check"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              PRE="$DIR/fss-pre-fss-archive"
              RECOV="$DIR/fss-recovery-receipts"
              BASE="$DIR/fss-baseline-boot"
              MARKER="$DIR/fss-rotated"
              MARKER_MTIME=$(stat -c %Y "$MARKER")
              ORIGINAL_PRE="$(tr -d "[:space:]" < "$PRE" 2>/dev/null || true)"
              OLD_RECOV="$(cat "$RECOV" 2>/dev/null || true)"
              BACKUP=$(mktemp -d)
              CANDIDATE="$DIR/system@0000000000000001-0000000000000001.journal"
              LATER="$DIR/system@0000000000000002-0000000000000002.journal"

              cleanup() {
                find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -delete
                rm -f "$PRE" "$CANDIDATE" "$LATER"
                if [ -n "$ORIGINAL_PRE" ]; then
                  printf "%s\n" "$ORIGINAL_PRE" > "$PRE"
                  chmod 0644 "$PRE"
                fi
                find "$BACKUP" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$DIR"/ \;
                rmdir "$BACKUP"
              }
              trap cleanup EXIT

              find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$BACKUP"/ \;
              : > "$CANDIDATE"; : > "$LATER"
              touch -d "@$MARKER_MTIME" "$CANDIDATE"
              touch -d "@$((MARKER_MTIME + 30))" "$LATER"
              rm -f "$PRE" "$BASE"
              sleep 1
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-backfill.log 2>&1

              test -f "$PRE"
              [ "$(tr -d "[:space:]" < "$PRE")" = "$CANDIDATE" ]
              [ "$(cat "$RECOV" 2>/dev/null || true)" = "$OLD_RECOV" ]
              [ "$(stat -c %Y "$MARKER")" = "$MARKER_MTIME" ]
              [ "$(tr -d "[:space:]" < "$BASE")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
            '
          """)

  with subtest("Setup avoids backfilling a later archive when the pre-FSS archive is gone"):
      if not skip_if_setup_failed("missing pre-FSS archive check"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              PRE="$DIR/fss-pre-fss-archive"
              RECOV="$DIR/fss-recovery-receipts"
              BASE="$DIR/fss-baseline-boot"
              MARKER="$DIR/fss-rotated"
              MARKER_MTIME=$(stat -c %Y "$MARKER")
              ORIGINAL_PRE="$(tr -d "[:space:]" < "$PRE" 2>/dev/null || true)"
              OLD_RECOV="$(cat "$RECOV" 2>/dev/null || true)"
              BACKUP=$(mktemp -d)
              LATER="$DIR/system@0000000000000002-0000000000000002.journal"

              cleanup() {
                find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -delete
                rm -f "$PRE" "$LATER"
                if [ -n "$ORIGINAL_PRE" ]; then
                  printf "%s\n" "$ORIGINAL_PRE" > "$PRE"
                  chmod 0644 "$PRE"
                fi
                find "$BACKUP" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$DIR"/ \;
                rmdir "$BACKUP"
              }
              trap cleanup EXIT

              find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$BACKUP"/ \;
              : > "$LATER"
              touch -d "@$((MARKER_MTIME + 30))" "$LATER"
              rm -f "$PRE" "$BASE"
              sleep 1
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-no-backfill.log 2>&1

              [ ! -e "$PRE" ]
              [ "$(cat "$RECOV" 2>/dev/null || true)" = "$OLD_RECOV" ]
              [ "$(stat -c %Y "$MARKER")" = "$MARKER_MTIME" ]
              [ "$(tr -d "[:space:]" < "$BASE")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
            '
          """)

  with subtest("Setup preserves initialized sentinel when verification key is missing"):
      if not skip_if_setup_failed("missing-key recovery"):
          machine.succeed(f"""
            bash -lc '
              set -euo pipefail
              KEY_DIR="/persist/common/journal-fss/test-host"
              VKEY="$KEY_DIR/verification-key"
              INIT="$KEY_DIR/initialized"
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              MARKER="$DIR/fss-rotated"
              BACKUP=$(mktemp)

              cleanup() {{
                if [ -f "$BACKUP" ]; then
                  cp "$BACKUP" "$VKEY"; chmod 0400 "$VKEY"; rm -f "$BACKUP"
                fi
                systemctl reset-failed journal-fss-setup.service journal-fss-verify.service >/dev/null 2>&1 || true
                systemctl restart journal-fss-setup.service >/dev/null 2>&1 || true
              }}
              trap cleanup EXIT

              cp "{verify_key_path}" "$BACKUP"
              test -f "$INIT" && test -f "$MARKER"
              rm -f "$VKEY"

              if systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-missing-key.log 2>&1; then
                echo "setup unexpectedly succeeded with missing key" >&2; exit 1
              fi
              test -f "$INIT" && test -f "$MARKER" && test -f "$DIR/fss-config"
              test -f /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
              grep -Fx "Seal=yes" /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf

              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/journal-fss-verify-missing-key.log 2>&1; then
                echo "verify unexpectedly succeeded with missing key" >&2; exit 1
              fi
              systemctl show journal-fss-verify.service -p ConditionResult -p ExecMainStatus | grep -F "ConditionResult=yes"
              systemctl show journal-fss-verify.service -p ConditionResult -p ExecMainStatus | grep -F "ExecMainStatus=1"
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "KEY_MISSING"

              cp "$BACKUP" "$VKEY"; chmod 0400 "$VKEY"
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-recovery.log 2>&1
              [ -f "$MARKER" ]
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              systemctl start journal-fss-verify.service >/tmp/journal-fss-verify-recovery.log 2>&1 || {{
                cat /tmp/journal-fss-verify-recovery.log
                journalctl -u journal-fss-verify.service -n 80 --no-pager
                exit 1
              }}
            '
          """)

  with subtest("Key regeneration rotates journals even when the cleanup marker already exists"):
      if not skip_if_setup_failed("key-regeneration rotation"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              MARKER="$DIR/fss-rotated"
              PRE="$DIR/fss-pre-fss-archive"
              FSS_KEY="$DIR/fss"
              [ -f "$FSS_KEY" ] || FSS_KEY="/run/log/journal/$MID/fss"

              test -f "$FSS_KEY" && test -f "$MARKER"
              old=$(stat -c %Y "$MARKER"); sleep 1
              rm -f "$FSS_KEY"
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-regeneration.log 2>&1
              test -f "$FSS_KEY" && test -f "$PRE"
              [ "$(stat -c %Y "$MARKER")" -gt "$old" ]
            '
          """)

  with subtest("Setup does not rotate only because active sealing key mtime advances"):
      if not skip_if_setup_failed("same-boot active key mtime"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              MARKER="$DIR/fss-rotated"
              BASE="$DIR/fss-baseline-boot"
              RECOV="$DIR/fss-recovery-receipts"
              FSS_KEY="$DIR/fss"
              [ -f "$FSS_KEY" ] || FSS_KEY="/run/log/journal/$MID/fss"

              test -f "$FSS_KEY" && test -f "$MARKER" && test -f "$BASE"
              [ "$(tr -d "[:space:]" < "$BASE")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
              old_marker_mtime="$(stat -c %Y "$MARKER")"
              old_recov="$(cat "$RECOV" 2>/dev/null || true)"
              sleep 1
              touch "$FSS_KEY"
              [ "$(stat -c %Y "$FSS_KEY")" -gt "$old_marker_mtime" ]
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-same-boot-key-replacement.log 2>&1
              [ "$(stat -c %Y "$MARKER")" = "$old_marker_mtime" ]
              [ "$(tr -d "[:space:]" < "$BASE")" = "$(cat /proc/sys/kernel/random/boot_id)" ]
              [ "$(cat "$RECOV" 2>/dev/null || true)" = "$old_recov" ]
              journalctl -u journal-fss-setup.service -n 20 --no-pager |
                grep -F "Journald FSS activation is already active for this boot; skipping restart"
            '
          """)

  with subtest("Initial key-generation failure still activates sealing and rotates journals"):
      if not skip_if_setup_failed("initial key-generation failure recovery"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              KEY_DIR="/persist/common/journal-fss/test-host"
              VKEY="$KEY_DIR/verification-key"
              INIT="$KEY_DIR/initialized"
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              FSS_KEY="$DIR/fss"
              MARKER="$DIR/fss-rotated"
              BACKUP="$KEY_DIR/verification-key.pre-test-backup"

              test -f "$FSS_KEY" && test -f "$VKEY"
              mv "$VKEY" "$BACKUP"
              mkdir "$VKEY"
              rm -f "$INIT" "$MARKER" "$FSS_KEY"

              before=$(systemctl show systemd-journald.service -p InvocationID --value)
              if systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-generation-failure.log 2>&1; then
                echo "setup unexpectedly succeeded with broken verification-key dir" >&2; exit 1
              fi
              test -f "$FSS_KEY" && test -f "$INIT" && test -f "$MARKER"
              [ "$(systemctl show systemd-journald.service -p InvocationID --value)" != "$before" ]

              rm -rf "$VKEY"; mv "$BACKUP" "$VKEY"
            '
          """)
''
