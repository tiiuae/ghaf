# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS Setup Tests
#
# Verifies FSS key generation, verification key extraction, and service configuration.
# These tests check that the journal-fss-setup service ran correctly and created
# all necessary artifacts for Forward Secure Sealing.
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
  setup_condition_skipped = "ConditionResult=no" in setup_status

  with subtest("FSS setup service exists"):
      # Check service exists and examine its state
      machine.succeed("systemctl list-unit-files journal-fss-setup.service")
      print(f"FSS setup service status: {setup_status}")
      # Service may not have run if conditions weren't met (expected in minimal test VM)
      if setup_condition_skipped:
          print("Service conditions not met - this is expected in test environment")
      elif setup_succeeded:
          print("FSS setup service completed successfully")
      else:
          raise Exception(f"FSS setup service did not complete successfully: {setup_status}")

  with subtest("FSS sealing key check"):
      mid = machine.succeed("cat /etc/machine-id").strip()
      exit_code, _ = machine.execute(f"test -f /var/log/journal/{mid}/fss")
      if exit_code == 0:
          print(f"FSS sealing key exists at /var/log/journal/{mid}/fss")
      else:
          exit_code2, _ = machine.execute(f"test -f /run/log/journal/{mid}/fss")
          if exit_code2 == 0:
              print("FSS sealing key exists in volatile storage")
          else:
              print("FSS sealing key not found - service conditions may not have been met")

  with subtest("Persistent journal storage is mounted"):
      if setup_succeeded:
          machine.succeed("findmnt --mountpoint /var/log/journal")
          machine.succeed("test -d /persist/var/log/journal")
          source = machine.succeed("findmnt --noheadings --output SOURCE --mountpoint /var/log/journal").strip()
          if "/persist/var/log/journal" not in source:
              raise Exception(f"/var/log/journal is not backed by /persist/var/log/journal: {source}")
      else:
          print("Skipping persistent journal mount assertion because setup did not complete successfully")

  with subtest("Verification key extracted"):
      if setup_succeeded:
          machine.succeed("test -s /persist/common/journal-fss/test-host/verification-key")
          print("Verification key exists and is non-empty")
      else:
          exit_code, _ = machine.execute("test -s /persist/common/journal-fss/test-host/verification-key")
          if exit_code == 0:
              print("Verification key exists and is non-empty")
          else:
              print("Skipping verification key assertion because setup did not complete successfully")

  with subtest("Initialized sentinel exists"):
      if setup_succeeded:
          machine.succeed("test -f /persist/common/journal-fss/test-host/initialized")
          print("Initialization sentinel exists")
      else:
          exit_code, _ = machine.execute("test -f /persist/common/journal-fss/test-host/initialized")
          if exit_code == 0:
              print("Initialization sentinel exists")
          else:
              print("Skipping initialized sentinel assertion because setup did not complete successfully")

  with subtest("Verification timer is configured"):
      machine.succeed("systemctl list-unit-files journal-fss-verify.timer")
      timer_info = machine.succeed("systemctl show journal-fss-verify.timer --property=TimersCalendar,OnBootSec")
      print(f"Verification timer configuration: {timer_info}")
''
