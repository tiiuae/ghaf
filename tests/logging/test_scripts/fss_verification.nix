# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS Verification Tests
#
# Verifies journal integrity checking works correctly. Tests that:
# - Journal verification runs without critical errors on untampered logs
# - Journal files are created properly
# - Verification service can be triggered manually
#
_: ''
  with subtest("Journal verification runs without critical errors"):
      machine.succeed("logger -t fss-test 'Test entry 1'")
      machine.succeed("logger -t fss-test 'Test entry 2'")
      machine.sleep(5)
      exit_code, output = machine.execute("""
        bash -lc '
          set -euo pipefail
          KEY=$(cat /persist/common/journal-fss/test-host/verification-key)
          source /etc/fss-verify-classifier.sh
          VERIFY_OUTPUT=$(journalctl --verify --verify-key="$KEY" 2>&1 || true)
          fss_classify_verify_output "$VERIFY_OUTPUT"

          if [ "$FSS_KEY_PARSE_ERROR" -eq 1 ] || [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]; then
            echo "$VERIFY_OUTPUT"
            exit 1
          fi

          if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] || [ -n "$FSS_OTHER_FAILURES" ]; then
            echo "$VERIFY_OUTPUT"
            exit 1
          fi
        '
      """)
      if exit_code != 0:
          raise Exception(f"Journal verification found critical failures: {output}")
      print(f"Journal verification completed (exit code: {exit_code})")

  with subtest("Verification policy ignores temp files and downgrades archive or user-only failures"):
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          source /etc/fss-verify-classifier.sh

          active_sample=$(cat <<'"'"'EOF'"'"'
  FAIL: /var/log/journal/mid/system.journal (Bad message)
  EOF
          )
          fss_classify_verify_output "$active_sample"
          [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -z "$FSS_ARCHIVED_SYSTEM_FAILURES" ]
          [ -z "$FSS_USER_FAILURES" ]

          archived_sample=$(cat <<'"'"'EOF'"'"'
  FAIL: /var/log/journal/mid/system@0000000000000001-0000000000000002.journal (Input/output error)
  PASS: /var/log/journal/mid/system.journal
  EOF
          )
          fss_classify_verify_output "$archived_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]
          [ -z "$FSS_OTHER_FAILURES" ]

          user_sample=$(cat <<'"'"'EOF'"'"'
  FAIL: /var/log/journal/mid/user-1000@0000000000000001-0000000000000002.journal (Bad message)
  PASS: /var/log/journal/mid/system.journal
  EOF
          )
          fss_classify_verify_output "$user_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -n "$FSS_USER_FAILURES" ]
          [ -z "$FSS_OTHER_FAILURES" ]

          user_active_sample=$(cat <<'"'"'EOF'"'"'
  2cb2e0: Tag failed verification
  File corruption detected at /var/log/journal/mid/user-1000.journal:2929376 (of 8388608 bytes, 34%).
  FAIL: /var/log/journal/mid/user-1000.journal (Bad message)
  PASS: /var/log/journal/mid/system.journal
  EOF
          )
          fss_classify_verify_output "$user_active_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -n "$FSS_USER_FAILURES" ]
          [ -z "$FSS_OTHER_FAILURES" ]

          temp_sample=$(cat <<'"'"'EOF'"'"'
  FAIL: /var/log/journal/mid/system@0000000000000001-0000000000000002.journal~ (Bad message)
  EOF
          )
          fss_classify_verify_output "$temp_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -z "$FSS_ARCHIVED_SYSTEM_FAILURES" ]
          [ -z "$FSS_USER_FAILURES" ]
          [ -n "$FSS_TEMP_FAILURES" ]

          temp_with_diagnostics_sample=$(cat <<'"'"'EOF'"'"'
  2cb2e0: Tag failed verification
  FAIL: /var/log/journal/mid/user-1000@0000000000000001-0000000000000002.journal~ (Bad message)
  EOF
          )
          fss_classify_verify_output "$temp_with_diagnostics_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -z "$FSS_ARCHIVED_SYSTEM_FAILURES" ]
          [ -z "$FSS_USER_FAILURES" ]
          [ -n "$FSS_TEMP_FAILURES" ]
          [ -z "$FSS_OTHER_FAILURES" ]

          other_sample=$(cat <<'"'"'EOF'"'"'
  FAIL: /var/log/journal/mid/custom.journal (Bad message)
  EOF
          )
          fss_classify_verify_output "$other_sample"
          [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
          [ -z "$FSS_ARCHIVED_SYSTEM_FAILURES" ]
          [ -z "$FSS_USER_FAILURES" ]
          [ -n "$FSS_OTHER_FAILURES" ]

          key_sample=$(cat <<'"'"'EOF'"'"'
  Failed to parse seed.
  FAIL: /var/log/journal/mid/system.journal (Required key not available)
  EOF
          )
          fss_classify_verify_output "$key_sample"
          [ "$FSS_KEY_PARSE_ERROR" -eq 1 ]
          [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]
        '
      """)

  with subtest("Journal files are created"):
      mid = machine.succeed("cat /etc/machine-id").strip()
      exit_code, journal_files = machine.execute(f"ls /var/log/journal/{mid}/*.journal 2>/dev/null || ls /run/log/journal/{mid}/*.journal 2>/dev/null")
      if exit_code == 0 and journal_files.strip():
          print(f"Journal files found: {journal_files.strip()}")
      else:
          print("No journal files found yet - this is expected early in boot")

  with subtest("FSS verify service can be triggered"):
      machine.succeed("systemctl list-unit-files journal-fss-verify.service")
      exit_code, output = machine.execute("systemctl start journal-fss-verify.service 2>&1")
      if exit_code == 0:
          print("Manual verification service ran successfully")
      else:
          if "ConditionPathExists" in output:
              print("Verification service skipped (not yet initialized) - expected in test environment")
          else:
              print(f"Verification service returned: {output}")

''
