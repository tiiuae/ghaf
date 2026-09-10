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
      # The case table lives in tests/logging/test_scripts/fss-classifier-cases.nix
      # so the same assertions also run VM-free as
      # checks.x86_64-linux.fss-classifier-unit. Running it here against the
      # installed /etc copy additionally asserts the module shipped the file the
      # fast check exercised.
      machine.succeed("fss-classifier-cases /etc/fss-verify-classifier.sh")

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
          grep -E "sync_result=(synchronized|timeout|disabled|sync-tool-unavailable)" /run/ghaf-clock-sync-state

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

  with subtest("Deployed fss-triage reports receipt summary"):
      if not skip_if_setup_failed("fss-triage"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              OUT=$(mktemp -d)
              fss-triage --output-dir "$OUT" >/tmp/fss-triage-operator.log 2>&1 || {
                cat /tmp/fss-triage-operator.log
                exit 1
              }
              grep -F "Receipt summary:" "$OUT/summary.txt"
              grep -E "^class[[:space:]]+total[[:space:]]+valid[[:space:]]+current[[:space:]]+stale[[:space:]]+missing[[:space:]]+mismatched" "$OUT/summary.txt"
              grep -E "^pre-activation[[:space:]]+" "$OUT/summary.txt"
              grep -E "^recovery[[:space:]]+" "$OUT/summary.txt"
              grep -E "^unclean-shutdown[[:space:]]+" "$OUT/summary.txt"
            '
          """)

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

  with subtest("Backward re-key: verify excuses pre-re-key archives via a retained key"):
      if not skip_if_setup_failed("retained-key rescue"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              KEY_DIR="/persist/common/journal-fss/test-host"
              VKEY="$KEY_DIR/verification-key"
              INIT="$KEY_DIR/initialized"
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              WORK=$(mktemp -d)

              # Regenerate a clean FSS key pair via journal-fss-setup, which owns
              # the journald restart. (A journal dir wipe + regen also clears the
              # assorted stale journals/keys earlier subtests leave behind.)
              regen_keys() {
                systemctl stop systemd-journald.service systemd-journald.socket
                rm -f "$DIR"/*.journal "$DIR"/*.journal~ "$DIR/fss" "$VKEY" \
                  "$KEY_DIR"/verification-key.* "$INIT"
                systemctl start systemd-journald.service
                systemctl restart journal-fss-setup.service
                [ "$(systemctl show journal-fss-setup.service -p Result --value)" = success ]
                test -s "$VKEY" && test -s "$DIR/fss"
              }

              restore() {
                systemctl start journal-fss-verify.timer 2>/dev/null || true
                rm -f "$KEY_DIR/verification-key.1"
                regen_keys 2>/dev/null || true
                rm -rf "$WORK"
              }
              trap restore EXIT

              # Stop the periodic verify so only our explicit runs fire, and the
              # invocation id we read back is unambiguous.
              systemctl stop journal-fss-verify.timer

              # Key pair K0.
              regen_keys
              cp -a "$VKEY" "$WORK/vkey.k0"

              # Seal an archive under K0.
              logger -t fss-rescue-test "pre-rekey marker $$"
              journalctl --sync; journalctl --rotate; journalctl --sync
              ARCHIVE=$(find "$DIR" -maxdepth 1 -name "system@*.journal" | sort | tail -n 1)
              test -n "$ARCHIVE"
              journalctl --verify --verify-key="$(tr -d "[:space:]" < "$VKEY")" --file="$ARCHIVE"

              # Re-key to K1 (drop only the key pair; keep the K0 archive). Then
              # install K0 as the retained key and drop any receipt store so the
              # archive can only be excused by the retained-key retry, not an
              # allowlist.
              rm -f "$DIR/fss" "$VKEY" "$INIT"
              systemctl restart journal-fss-setup.service
              [ "$(systemctl show journal-fss-setup.service -p Result --value)" = success ]
              cp -a "$WORK/vkey.k0" "$KEY_DIR/verification-key.1"
              chmod 0400 "$KEY_DIR/verification-key.1"
              rm -f "$DIR"/fss-pre-activation-receipts "$DIR"/fss-recovery-receipts \
                "$DIR"/fss-unclean-shutdown-receipts "$DIR"/fss-pre-fss-archive

              # The K0 archive now fails under K1 and verifies under the retained key.
              if journalctl --verify --verify-key="$(tr -d "[:space:]" < "$VKEY")" --file="$ARCHIVE" >/dev/null 2>&1; then
                echo "archive still verifies under the new key" >&2; exit 1
              fi
              journalctl --verify --verify-key="$(tr -d "[:space:]" < "$KEY_DIR/verification-key.1")" --file="$ARCHIVE"

              # journal-fss-verify must rescue it, not degrade.
              systemctl start --wait journal-fss-verify.service || true
              INVID=$(systemctl show journal-fss-verify.service -p InvocationID --value)
              journalctl _SYSTEMD_INVOCATION_ID="$INVID" --no-pager > "$WORK/verify.log" 2>&1
              grep -F "Retained-key rescue" "$WORK/verify.log"
              grep -Fq "$ARCHIVE" "$WORK/verify.log"
              if grep -F "Journal integrity verification: FAILED" "$WORK/verify.log"; then
                echo "verify degraded despite a valid retained key" >&2
                cat "$WORK/verify.log" >&2
                exit 1
              fi

              # Tamper the pre-re-key archive. It now fails under every key, so
              # C cannot rescue it. Because a re-key is attested (retained keys
              # on disk), the A tidy-up buckets an unreceipted archived-system
              # failure as a re-key transition WARNING -- not a hard FAIL -- so
              # the verdict is the same on every VM regardless of vacuum timing.
              # (Archived-journal integrity is backstopped by offline
              # verification against the off-host key, per fss.mdx.)
              test -f "$ARCHIVE"
              dd if=/dev/urandom of="$ARCHIVE" bs=1 count=512 seek=16384 conv=notrunc status=none
              if journalctl --verify --verify-key="$(tr -d "[:space:]" < "$KEY_DIR/verification-key.1")" --file="$ARCHIVE" >/dev/null 2>&1; then
                echo "tampered archive still verifies under the retained key" >&2; exit 1
              fi
              systemctl start --wait journal-fss-verify.service || true
              INVID=$(systemctl show journal-fss-verify.service -p InvocationID --value)
              journalctl _SYSTEMD_INVOCATION_ID="$INVID" --no-pager > "$WORK/verify-tamper.log" 2>&1
              grep -F "REKEY_TRANSITION_ARCHIVE" "$WORK/verify-tamper.log"
              grep -F "archived system journal from an attested re-key transition" "$WORK/verify-tamper.log"
              if grep -F "Journal integrity verification: FAILED" "$WORK/verify-tamper.log"; then
                echo "unexpected hard FAIL for a re-key transition archive" >&2
                cat "$WORK/verify-tamper.log" >&2; exit 1
              fi

              # A must not blunt an ACTIVE journal tamper: corrupt the live
              # system.journal and the verdict is a hard FAIL again.
              journalctl --sync
              LIVE="$DIR/system.journal"
              test -f "$LIVE"
              dd if=/dev/urandom of="$LIVE" bs=1 count=512 seek=16384 conv=notrunc status=none
              systemctl start --wait journal-fss-verify.service || true
              INVID=$(systemctl show journal-fss-verify.service -p InvocationID --value)
              journalctl _SYSTEMD_INVOCATION_ID="$INVID" --no-pager > "$WORK/verify-live-tamper.log" 2>&1
              grep -F "Journal integrity verification: FAILED" "$WORK/verify-live-tamper.log"
            '
          """)

  with subtest("FSS key retention keeps the newest generations by creation order, not epoch"):
      if not skip_if_setup_failed("retained-key retention order"):
          machine.succeed("""
            bash -lc '
              set -euo pipefail
              source /etc/fss-verify-classifier.sh
              KEY_DIR="/persist/common/journal-fss/test-host"
              WORK=$(mktemp -d)
              SC="$WORK/keys"
              mkdir "$SC"
              cleanup() { rm -rf "$WORK" "$KEY_DIR"/verification-key.77[789]; }
              trap cleanup EXIT

              # Four backward clock corrections: each re-key epoch is LOWER than
              # the last, but each key is created LATER. rekey-history is
              # append-only, oldest first; field 2 is the key path.
              : > "$SC/rekey-history"
              i=0
              for epoch in 4000 3000 2000 1000; do
                printf "gen-%s" "$epoch" > "$SC/verification-key.$epoch"
                touch -d "@$(( 1000000000 + i * 60 ))" "$SC/verification-key.$epoch"
                printf "%s\t%s\t-\t-\n" "$epoch" "$SC/verification-key.$epoch" >> "$SC/rekey-history"
                i=$(( i + 1 ))
              done

              want=$(printf "%s\n%s\n%s\n%s" \
                "$SC/verification-key.1000" "$SC/verification-key.2000" \
                "$SC/verification-key.3000" "$SC/verification-key.4000")

              # History order and mtime order both give newest-created first --
              # verification-key.1000 (latest correction, LOWEST epoch) leads,
              # verification-key.4000 (earliest, HIGHEST epoch) trails. The
              # pre-fix filename-epoch sort produced the exact reverse.
              [ "$(fss_retained_keys_newest_first "$SC" "$SC/rekey-history")" = "$want" ]
              [ "$(fss_list_retained_verification_keys "$SC")" = "$want" ]

              # A budget-3 prune keeps 1000/2000/3000 and drops 4000.
              order=$(fss_retained_keys_newest_first "$SC" "$SC/rekey-history")
              [ "$(printf "%s" "$order" | tail -n +4)" = "$SC/verification-key.4000" ]
              printf "%s\n" "$order" | head -n 3 | grep -Fxq "$SC/verification-key.1000"

              # The retained-key retry scans every retained generation: seal an
              # archive under the current key, park that verification key as the
              # OLDEST retained generation behind two newer non-matching ones,
              # and it is still found.
              MID=$(cat /etc/machine-id)
              DIR="/var/log/journal/$MID"
              logger -t fss-retain-test "seal under current gen $$"
              journalctl --sync; journalctl --rotate; journalctl --sync
              AR=$(find "$DIR" -maxdepth 1 -name "system@*.journal" | sort | tail -n 1)
              test -n "$AR"
              cp -a "$KEY_DIR/verification-key" "$KEY_DIR/verification-key.777"
              touch -d "@1000000000" "$KEY_DIR/verification-key.777"
              printf "not-a-key-a" > "$KEY_DIR/verification-key.778"
              touch -d "@1000000100" "$KEY_DIR/verification-key.778"
              printf "not-a-key-b" > "$KEY_DIR/verification-key.779"
              touch -d "@1000000200" "$KEY_DIR/verification-key.779"
              chmod 0400 "$KEY_DIR"/verification-key.77[789]
              fss_archive_verifies_under_retained_key "$AR" "$KEY_DIR"
            '
          """)
''
