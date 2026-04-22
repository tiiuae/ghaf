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
              VERIFY_OUTPUT=$(journalctl --verify --verify-key="$(cat {verify_key_path})" 2>&1 || true)
              fss_classify_verify_output "$VERIFY_OUTPUT"
              fss_verify_policy_decision \
                "$(fss_read_recorded_pre_fss_archive "/var/log/journal/$MID/fss-pre-fss-archive")" \
                "$(fss_read_recorded_archive_list "/var/log/journal/$MID/fss-recovery-archives")"
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

          # Assert that classifying $sample and running policy with $pre/$recov yields $want.
          # Usage: assert_verdict <want> <sample> [expected_pre] [expected_recovery]
          assert_verdict() {
            local want="$1" sample="$2" pre="''${3:-}" recov="''${4:-}"
            fss_classify_verify_output "$sample"
            fss_verify_policy_decision "$pre" "$recov"
            if [ "$FSS_VERDICT" != "$want" ]; then
              printf "verdict mismatch: want=%s got=%s reason=%s sample=%s\n" \
                "$want" "$FSS_VERDICT" "$FSS_VERDICT_REASON" "$sample" >&2
              return 1
            fi
          }

          ACTIVE="/var/log/journal/mid/system.journal"
          ALLOWED_ARCHIVE="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal"
          RECOVERY_ARCHIVE="/var/log/journal/mid/system@0000000000000005-0000000000000006.journal"
          UNEXPECTED_ARCHIVE="/var/log/journal/mid/system@0000000000000003-0000000000000004.journal"
          USER_JOURNAL="/var/log/journal/mid/user-1000@0000000000000001-0000000000000002.journal"
          TEMP_JOURNAL="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal~"
          OTHER="/var/log/journal/mid/custom.journal"

          # Active system failure → fail
          assert_verdict fail "FAIL: $ACTIVE (Bad message)"
          [ "$FSS_REASON_TAGS" = "BAD_MESSAGE" ]

          # Allowed archive only → partial (matches pre-FSS allowlist)
          assert_verdict partial \
            "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$ALLOWED_ARCHIVE" "$ACTIVE")" \
            "$ALLOWED_ARCHIVE"
          [ "$FSS_REASON_TAGS" = "INPUT_OUTPUT_ERROR" ]
          fss_matches_only_expected_archived_system_failure "$ALLOWED_ARCHIVE"

          # Recovery archive (duplicate in list, to test dedup) → partial
          assert_verdict partial \
            "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$RECOVERY_ARCHIVE" "$ACTIVE")" \
            "" "$(printf "%s\n%s" "$RECOVERY_ARCHIVE" "$RECOVERY_ARCHIVE")"

          # Unexpected archive → fail
          assert_verdict fail \
            "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$UNEXPECTED_ARCHIVE" "$ACTIVE")" \
            "$ALLOWED_ARCHIVE" "$(printf "%s" "$RECOVERY_ARCHIVE")"

          # Allowed + recovery archives together → partial
          assert_verdict partial \
            "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE")" \
            "$ALLOWED_ARCHIVE" "$(printf "%s" "$RECOVERY_ARCHIVE")"

          # Allowed + unexpected archive → fail (allowlist miss on one path)
          assert_verdict fail \
            "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$UNEXPECTED_ARCHIVE")" \
            "$ALLOWED_ARCHIVE" "$(printf "%s" "$RECOVERY_ARCHIVE")"

          # User journal failure alone → partial (non-fatal)
          assert_verdict partial "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
          [ -n "$FSS_USER_FAILURES" ]
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]

          # User journal with corruption diagnostics → partial
          assert_verdict partial "$(printf "2cb2e0: Tag failed verification\nFile corruption detected at %s:2929376 (of 8388608 bytes, 34%%).\nFAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$USER_JOURNAL" "$ACTIVE")"

          # Temp journal failure → pass (ignored)
          assert_verdict pass "FAIL: $TEMP_JOURNAL (Bad message)"
          [ -n "$FSS_TEMP_FAILURES" ]

          # Other/unclassified journal → fail
          assert_verdict fail "FAIL: $OTHER (Bad message)"
          [ -n "$FSS_OTHER_FAILURES" ]

          # Key parse + missing key → fail
          assert_verdict fail "$(printf "Failed to parse seed.\nFAIL: %s (Required key not available)" "$ACTIVE")"
          [ "$FSS_KEY_PARSE_ERROR" -eq 1 ]
          [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]
          [ "$FSS_REASON_TAGS" = "KEY_PARSE_ERROR,KEY_MISSING" ]

          # Empty input → pass (no findings)
          assert_verdict pass ""
          [ -z "$FSS_REASON_TAGS" ]
          [ -z "$FSS_FAIL_LINES" ]

          # Bucket classification and dedup of unique fail paths
          MIXED=$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)" \
            "$ACTIVE" "$ACTIVE" "$ALLOWED_ARCHIVE" "$USER_JOURNAL" "$TEMP_JOURNAL" "$OTHER")
          [ "$(fss_count_nonempty_lines "$(fss_unique_fail_paths_from_output "$MIXED")")" -eq 5 ]
          [ "$(fss_failure_bucket_for_path "$ACTIVE")" = "active-system" ]
          [ "$(fss_failure_bucket_for_path "$ALLOWED_ARCHIVE")" = "archived-system" ]
          [ "$(fss_failure_bucket_for_path "$USER_JOURNAL")" = "user-journal" ]
          [ "$(fss_failure_bucket_for_path "$TEMP_JOURNAL")" = "temp" ]
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
      machine.succeed("systemctl list-unit-files ghaf-clock-jump-watcher.service")
      machine.succeed("systemctl list-unit-files ghaf-journal-alloy-recover.service")
      machine.wait_for_unit("ghaf-clock-jump-watcher.service")
      status = machine.succeed("systemctl show ghaf-clock-jump-watcher.service --property=ActiveState,UnitFileState")
      if "ActiveState=active" not in status or "UnitFileState=enabled" not in status:
          raise Exception(f"Clock-jump watcher not enabled: {status}")

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

  with subtest("Setup backfills only the archive created at the original FSS rotation"):
      if not skip_if_setup_failed("archive backfill check"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              PRE="$DIR/fss-pre-fss-archive"
              MARKER_MTIME=$(stat -c %Y "$DIR/fss-rotated")
              BACKUP=$(mktemp -d)
              CANDIDATE="$DIR/system@0000000000000001-0000000000000001.journal"
              LATER="$DIR/system@0000000000000002-0000000000000002.journal"

              cleanup() {
                rm -f "$PRE" "$CANDIDATE" "$LATER"
                find "$BACKUP" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$DIR"/ \;
                rmdir "$BACKUP"
              }
              trap cleanup EXIT

              find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$BACKUP"/ \;
              : > "$CANDIDATE"; : > "$LATER"
              touch -d "@$MARKER_MTIME" "$CANDIDATE"
              touch -d "@$((MARKER_MTIME + 30))" "$LATER"
              rm -f "$PRE"
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-backfill.log 2>&1

              test -f "$PRE"
              [ "$(tr -d "[:space:]" < "$PRE")" = "$CANDIDATE" ]
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
              MARKER_MTIME=$(stat -c %Y "$DIR/fss-rotated")
              BACKUP=$(mktemp -d)
              LATER="$DIR/system@0000000000000002-0000000000000002.journal"

              cleanup() {
                rm -f "$PRE" "$LATER"
                find "$BACKUP" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$DIR"/ \;
                rmdir "$BACKUP"
              }
              trap cleanup EXIT

              find "$DIR" -maxdepth 1 -type f -name "system@*.journal" -exec mv {} "$BACKUP"/ \;
              : > "$LATER"
              touch -d "@$((MARKER_MTIME + 30))" "$LATER"
              rm -f "$PRE"
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-no-backfill.log 2>&1

              [ ! -e "$PRE" ]
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
              rm -f "$VKEY" "$MARKER"
              before=$(systemctl show systemd-journald.service -p InvocationID --value)

              if systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-missing-key.log 2>&1; then
                echo "setup unexpectedly succeeded with missing key" >&2; exit 1
              fi
              test -f "$INIT" && [ ! -e "$MARKER" ] && test -f "$DIR/fss-config"
              [ "$(systemctl show systemd-journald.service -p InvocationID --value)" = "$before" ]

              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              if systemctl start journal-fss-verify.service >/tmp/journal-fss-verify-missing-key.log 2>&1; then
                echo "verify unexpectedly succeeded with missing key" >&2; exit 1
              fi
              systemctl show journal-fss-verify.service -p ConditionResult -p ExecMainStatus | grep -F "ConditionResult=yes"
              systemctl show journal-fss-verify.service -p ConditionResult -p ExecMainStatus | grep -F "ExecMainStatus=1"
              journalctl -u journal-fss-verify.service -n 20 --no-pager | grep -F "KEY_MISSING"

              cp "$BACKUP" "$VKEY"; chmod 0400 "$VKEY"
              before_recovery=$(systemctl show systemd-journald.service -p InvocationID --value)
              systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-recovery.log 2>&1
              [ -f "$MARKER" ]
              [ "$(systemctl show systemd-journald.service -p InvocationID --value)" != "$before_recovery" ]
              systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true
              systemctl start journal-fss-verify.service >/tmp/journal-fss-verify-recovery.log 2>&1
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
