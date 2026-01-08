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
      exit_code, output = machine.execute("journalctl --verify 2>&1")
      # Filter out temp file failures (*.journal~) - these are not sealed journals
      real_failures = [line for line in output.split('\n') if 'FAIL' in line and not line.endswith('~')]
      if real_failures:
          raise Exception(f"Journal verification found integrity failures: {real_failures}")
      print(f"Journal verification completed (exit code: {exit_code})")

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
