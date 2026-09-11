# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS Setup Tests
#
# Verifies FSS key generation, verification key extraction, and service configuration.
# These tests check that the journal-fss-setup service ran correctly and created
# all necessary artifacts for Forward Secure Sealing.
#
{ faultLib, ... }: ''
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
          machine.succeed(f"test \"$(stat -c '%U:%G %a' /var/log/journal/{mid}/fss)\" = 'root:root 600'")
      else:
          exit_code2, _ = machine.execute(f"test -f /run/log/journal/{mid}/fss")
          if exit_code2 == 0:
              print("FSS sealing key exists in volatile storage")
              machine.succeed(f"test \"$(stat -c '%U:%G %a' /run/log/journal/{mid}/fss)\" = 'root:root 600'")
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

  with subtest("Runtime FSS activation config is written"):
      if setup_succeeded:
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              test -f /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
              grep -Fx "[Journal]" /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
              grep -Fx "Seal=yes" /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf
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
            '
          """)
      else:
          print("Skipping runtime activation assertion because setup did not complete successfully")

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


  with subtest("Key generation fails closed on a durability barrier: sealing key"):
      # Fresh state so the non-force generate_fss_key_pair path runs; the
      # sealing key's flush is failed by path, so it cannot land on some
      # other fsync the way an ordinal injection could. Exercises the
      # initial-keygen path (generate_fss_key_pair, no --force).
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          MID=$(cat /etc/machine-id)
          FSS_KEY_FILE="/var/log/journal/$MID/fss"
          KEY_DIR=/persist/common/journal-fss/test-host
          JFS_BIN=$(systemctl cat journal-fss-setup.service | sed -n "s/^ExecStart=//p")

          JD="/var/log/journal/$MID"
          T0=$(date "+%Y-%m-%d %H:%M:%S")
          # Isolate: nothing else may start the unit while we drive it by hand.
          systemctl mask --runtime journal-fss-setup.service
          systemctl stop journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE" "$KEY_DIR/verification-key" "$KEY_DIR/initialized"

          EXIT=0
          LD_PRELOAD=${faultLib} FSS_FSYNC_FAIL_GLOB="$FSS_KEY_FILE" \
            "$JFS_BIN" >/tmp/inject-sealing.log 2>&1 || EXIT=$?

          echo "DIAG log:"; cat /tmp/inject-sealing.log
          echo "DIAG resolved sealing key path per attempt:"
          grep -E "Sealing key:|FSS sealing key already exists at" /tmp/inject-sealing.log || true
          echo "DIAG unit log since T0:"
          journalctl -u journal-fss-setup.service --since "$T0" --no-pager | tail -20 || true
          # Assert the injection landed on the intended flush first: the fail
          # line alone cannot tell a working barrier from an injection that
          # never fired, which is how the previous ordinal injection passed
          # while letting key generation complete.
          grep -Fx "fss-fsync-fault: EIO $FSS_KEY_FILE" /tmp/inject-sealing.log
          grep -F "Could not flush the new sealing key" /tmp/inject-sealing.log
          if grep -Fq "FSS verification key extracted successfully" /tmp/inject-sealing.log; then
            echo "unexpected: extracted successfully after an injected sealing-key sync failure" >&2
            exit 1
          fi
          [ ! -s "$KEY_DIR/verification-key" ]
          [ "$EXIT" -ne 0 ]

          # No self-heal for a leftover unsynced FSS_KEY_FILE with no
          # verification key (the "already exists" branch fails again), so
          # recovery here means a full fresh regeneration, not a retry.
          systemctl reset-failed journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE"
          "$JFS_BIN" >/tmp/recover-sealing.log 2>&1
          grep -F "FSS verification key extracted successfully" /tmp/recover-sealing.log
          test -s "$KEY_DIR/verification-key"
          systemctl unmask --runtime journal-fss-setup.service

          # Everything here was sealed under the key pair this subtest just
          # destroyed. Moving only the archives it created left any earlier
          # un-receipted one behind to fail verify, at random.
          mkdir -p /tmp/fss-inject-aside
          find "$JD" -maxdepth 1 -name "system@*.journal" \
            -exec mv -t /tmp/fss-inject-aside {} +

          systemctl start journal-fss-verify.service
          systemctl show journal-fss-verify.service --property=Result --value | grep -Fx success
        '
      """)

  with subtest("Key generation fails closed on a durability barrier: temp verification key"):
      # The flush of $KEY_DIR/.verification-key.new.$$, before the atomic
      # rename installs it. $$ is the PID of the setup process itself,
      # unknown before launch, so an ordinal injection could never target
      # this barrier -- a glob can. Failing here must leave no key and no
      # temp behind.
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          MID=$(cat /etc/machine-id)
          FSS_KEY_FILE="/var/log/journal/$MID/fss"
          KEY_DIR=/persist/common/journal-fss/test-host
          JFS_BIN=$(systemctl cat journal-fss-setup.service | sed -n "s/^ExecStart=//p")

          JD="/var/log/journal/$MID"
          systemctl mask --runtime journal-fss-setup.service
          systemctl stop journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE" "$KEY_DIR/verification-key" "$KEY_DIR/initialized"

          EXIT=0
          LD_PRELOAD=${faultLib} FSS_FSYNC_FAIL_GLOB="$KEY_DIR/.verification-key.new.*" \
            "$JFS_BIN" >/tmp/inject-vktmp.log 2>&1 || EXIT=$?

          echo "DIAG log:"; cat /tmp/inject-vktmp.log
          grep -F "fss-fsync-fault: EIO $KEY_DIR/.verification-key.new." /tmp/inject-vktmp.log
          grep -F "Could not flush the new verification key to durable storage" /tmp/inject-vktmp.log
          if grep -Fq "FSS verification key extracted successfully" /tmp/inject-vktmp.log; then
            echo "unexpected: extracted successfully after an injected temp-key sync failure" >&2
            exit 1
          fi
          # Nothing installed and nothing left behind: the rename never ran.
          [ ! -s "$KEY_DIR/verification-key" ]
          if ls "$KEY_DIR"/.verification-key.new.* >/dev/null 2>&1; then
            echo "unexpected: temp verification key left behind after a failed flush" >&2
            exit 1
          fi
          [ "$EXIT" -ne 0 ]

          # Same recovery as the sealing-key barrier: a sealing key with no
          # verification key needs a fresh pair, not a retry.
          systemctl reset-failed journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE"
          "$JFS_BIN" >/tmp/recover-vktmp.log 2>&1
          grep -F "FSS verification key extracted successfully" /tmp/recover-vktmp.log
          test -s "$KEY_DIR/verification-key"
          systemctl unmask --runtime journal-fss-setup.service

          mkdir -p /tmp/fss-inject-aside
          find "$JD" -maxdepth 1 -name "system@*.journal" \
            -exec mv -t /tmp/fss-inject-aside {} +

          systemctl start journal-fss-verify.service
          systemctl show journal-fss-verify.service --property=Result --value | grep -Fx success
        '
      """)

  with subtest("Key generation logs an undurable install but fails closed: published key flush"):
      # durable_write first barrier: the fsync of the installed
      # $KEY_DIR/verification-key itself. KEY_DURABILITY_FAILED (fss.nix)
      # makes this exit non-zero even though the key itself is complete,
      # matching the re-key path's own barrier.
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          MID=$(cat /etc/machine-id)
          FSS_KEY_FILE="/var/log/journal/$MID/fss"
          KEY_DIR=/persist/common/journal-fss/test-host
          JFS_BIN=$(systemctl cat journal-fss-setup.service | sed -n "s/^ExecStart=//p")

          JD="/var/log/journal/$MID"
          systemctl mask --runtime journal-fss-setup.service
          systemctl stop journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE" "$KEY_DIR/verification-key" "$KEY_DIR/initialized"

          EXIT=0
          LD_PRELOAD=${faultLib} FSS_FSYNC_FAIL_GLOB="$KEY_DIR/verification-key" \
            "$JFS_BIN" >/tmp/inject-install.log 2>&1 || EXIT=$?

          echo "DIAG log:"; cat /tmp/inject-install.log
          grep -Fx "fss-fsync-fault: EIO $KEY_DIR/verification-key" /tmp/inject-install.log
          grep -F "Could not flush $KEY_DIR/verification-key to durable storage" /tmp/inject-install.log
          grep -F "New verification key installed but not durable" /tmp/inject-install.log
          grep -F "FSS setup finished but the verification key is not confirmed durable" /tmp/inject-install.log
          if grep -Fq "FSS verification key extracted successfully" /tmp/inject-install.log; then
            echo "unexpected: extracted successfully after an injected install-sync failure" >&2
            exit 1
          fi
          test -s "$KEY_DIR/verification-key"
          [ "$EXIT" -ne 0 ]

          # Regenerates the sealing key fresh too (reset above clears
          # FSS_KEY_FILE), orphaning the original-boot archives the same
          # way barrier 1'"'"'s recovery does.
          systemctl reset-failed journal-fss-setup.service 2>/dev/null || true
          systemctl unmask --runtime journal-fss-setup.service
          systemctl restart journal-fss-setup.service
          systemctl show journal-fss-setup.service --property=Result --value | grep -Fx success

          mkdir -p /tmp/fss-inject-aside
          find "$JD" -maxdepth 1 -name "system@*.journal" \
            -exec mv -t /tmp/fss-inject-aside {} +

          systemctl start journal-fss-verify.service
          systemctl show journal-fss-verify.service --property=Result --value | grep -Fx success
        '
      """)

  with subtest("Key generation logs an undurable install but fails closed: published directory flush"):
      # durable_write second barrier: the fsync of $KEY_DIR, which is what
      # makes the rename itself durable. Targeting the directory and not the
      # file proves the two are separate barriers -- the file flush must be
      # seen to succeed here, or this subtest is just the previous one again.
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          MID=$(cat /etc/machine-id)
          FSS_KEY_FILE="/var/log/journal/$MID/fss"
          KEY_DIR=/persist/common/journal-fss/test-host
          JFS_BIN=$(systemctl cat journal-fss-setup.service | sed -n "s/^ExecStart=//p")

          JD="/var/log/journal/$MID"
          systemctl mask --runtime journal-fss-setup.service
          systemctl stop journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE" "$KEY_DIR/verification-key" "$KEY_DIR/initialized"

          EXIT=0
          LD_PRELOAD=${faultLib} FSS_FSYNC_FAIL_GLOB="$KEY_DIR" \
            "$JFS_BIN" >/tmp/inject-keydir.log 2>&1 || EXIT=$?

          echo "DIAG log:"; cat /tmp/inject-keydir.log
          grep -Fx "fss-fsync-fault: EIO $KEY_DIR" /tmp/inject-keydir.log
          grep -F "Could not flush $KEY_DIR to durable storage" /tmp/inject-keydir.log
          # The file flush must have gone through: this is the directory
          # barrier, not the one the previous subtest already covers.
          if grep -Fq "Could not flush $KEY_DIR/verification-key to durable storage" /tmp/inject-keydir.log; then
            echo "unexpected: the published-file flush failed too; this is not the directory barrier" >&2
            exit 1
          fi
          grep -F "New verification key installed but not durable" /tmp/inject-keydir.log
          grep -F "FSS setup finished but the verification key is not confirmed durable" /tmp/inject-keydir.log
          test -s "$KEY_DIR/verification-key"
          [ "$EXIT" -ne 0 ]

          systemctl reset-failed journal-fss-setup.service 2>/dev/null || true
          systemctl unmask --runtime journal-fss-setup.service
          systemctl restart journal-fss-setup.service
          systemctl show journal-fss-setup.service --property=Result --value | grep -Fx success

          mkdir -p /tmp/fss-inject-aside
          find "$JD" -maxdepth 1 -name "system@*.journal" \
            -exec mv -t /tmp/fss-inject-aside {} +

          systemctl start journal-fss-verify.service
          systemctl show journal-fss-verify.service --property=Result --value | grep -Fx success
        '
      """)

  with subtest("Key generation control run: the shim loaded but matching nothing succeeds"):
      # Negative control for all four barriers above, and for the shim
      # itself: same preload, a glob that matches no path, so a green run
      # here means the failures above came from the injection and not from
      # loading the library. Also restores real key material for the
      # subtests after this file, and clears the archives the regeneration
      # orphaned so the reboot test right after sees a verifiable state.
      machine.succeed("""
        bash -lc '
          set -euo pipefail
          MID=$(cat /etc/machine-id)
          FSS_KEY_FILE="/var/log/journal/$MID/fss"
          KEY_DIR=/persist/common/journal-fss/test-host
          JD="/var/log/journal/$MID"
          JFS_BIN=$(systemctl cat journal-fss-setup.service | sed -n "s/^ExecStart=//p")

          systemctl mask --runtime journal-fss-setup.service
          systemctl stop journal-fss-setup.service 2>/dev/null || true
          rm -f "$FSS_KEY_FILE" "$KEY_DIR/verification-key" "$KEY_DIR/initialized"

          LD_PRELOAD=${faultLib} FSS_FSYNC_FAIL_GLOB="/nonexistent/matches-nothing" \
            "$JFS_BIN" >/tmp/control-run.log 2>&1
          grep -F "FSS verification key extracted successfully" /tmp/control-run.log
          if grep -Fq "fss-fsync-fault: EIO" /tmp/control-run.log; then
            echo "unexpected: the shim injected a failure with a non-matching glob" >&2
            exit 1
          fi

          mkdir -p /tmp/fss-inject-aside
          find "$JD" -maxdepth 1 -name "system@*.journal" \
            -exec mv -t /tmp/fss-inject-aside {} +

          systemctl reset-failed journal-fss-setup.service 2>/dev/null || true
          systemctl unmask --runtime journal-fss-setup.service
          systemctl restart journal-fss-setup.service
          systemctl is-active --quiet journal-fss-setup.service || systemctl is-failed --quiet journal-fss-setup.service
        '
      """)

''
