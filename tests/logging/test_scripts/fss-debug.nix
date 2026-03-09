# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# FSS (Forward Secure Sealing) Deep Debug Script
#
# Produces a local evidence packet for FSS incidents. Unlike `fss-test`, which
# answers "is FSS healthy enough right now?", `fss-debug` captures the runtime
# layout and the surrounding journald/identity context needed to explain why the
# current component is passing, warning, or failing.
#
# The packet is designed for root-cause analysis on deployed systems:
# - FSS runtime layout (`machine-id`, sealing key path, verification key path)
# - shared identity files (`/persist/common/ghaf`, `/etc/common/ghaf`, device-id)
# - unit state and recent logs for setup/verify/journald/recovery services
# - current journald configuration and mounts
# - full `journalctl --verify` output plus per-file isolates for failed journals
# - an explicit summary that classifies failures with the same policy as
#   `journal-fss-verify.service` and `fss-test`
#
# Usage:
#   sudo fss-debug
#   sudo fss-debug --out-dir /tmp/fss-debug
#   sudo fss-debug --failed-file-limit 32 --no-fss-test
#
{
  writeShellApplication,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  procps,
  systemd,
  util-linux,
}:
let
  verifyClassifierLib = builtins.readFile ../../../modules/common/logging/fss-verify-classifier.sh;
  runtimeLayoutLib = builtins.readFile ../../../modules/common/logging/fss-runtime-layout.sh;
in
writeShellApplication {
  name = "fss-debug";
  runtimeInputs = [
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    procps
    systemd
    util-linux
  ];
  text = ''
            set -euo pipefail

            ${verifyClassifierLib}
            ${runtimeLayoutLib}

            OUT_DIR="/var/tmp/fss-debug-$(date -u +%Y%m%dT%H%M%SZ)"
            SERVICE_LOG_LINES=150
            JOURNALD_LOG_LINES=400
            BOOT_LOG_LINES=300
            FAILED_FILE_LIMIT=16
            RUN_FSS_TEST=1
            INCLUDE_DMESG=1

            VERIFY_KEY=""
            VERIFY_KEY_BYTES=0
            VERIFY_KEY_STATE="missing"
            GHAF_SHARED_HOSTNAME=""
            GHAF_SHARED_ID=""
            GHAF_SHARED_UUID=""
            GHAF_DEVICE_ID=""
            GHAF_HOSTNAME_FILE=""
            GHAF_ID_FILE=""
            GHAF_UUID_FILE=""
            GHAF_DEVICE_ID_FILE=""

            log() {
              printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2
            }

            dedent_block() {
              sed 's/^    //'
            }

            usage() {
              cat <<'EOF' | dedent_block
        Usage: fss-debug [options]

        Create a local evidence packet for Forward Secure Sealing incidents.
        The packet contains:
        - system and identity context
        - FSS runtime path discovery
        - journald and FSS unit status/logs
        - full journal verification output
        - per-file verification for failed journal files
        - a summary classifying the result as clean, warning-only, key defect, or active failure

        Options:
          --out-dir <path>            Output directory
          --service-log-lines <n>     Recent unit log lines to capture (default: 150)
          --journald-log-lines <n>    Recent systemd-journald log lines to capture (default: 400)
          --boot-log-lines <n>        Recent boot log lines to capture (default: 300)
          --failed-file-limit <n>     Max failed journal files to re-verify individually (default: 16)
          --no-fss-test               Skip running fss-test
          --skip-dmesg                Skip dmesg capture
          --help                      Show this help

        Notes:
        - Run as root for complete output.
        - Verification key contents are never written to the report.
        - The report directory contains both raw command output and a summary.
    EOF
            }

            require_root() {
              if [ "$(id -u)" -ne 0 ]; then
                printf 'error: fss-debug must be run as root\n' >&2
                exit 2
              fi
            }

            require_numeric() {
              local value="$1"
              local label="$2"

              if ! [[ $value =~ ^[0-9]+$ ]]; then
                printf 'error: %s must be a non-negative integer, got %s\n' "$label" "$value" >&2
                exit 2
              fi
            }

            while [[ $# -gt 0 ]]; do
              case "$1" in
              --out-dir)
                OUT_DIR="$2"
                shift 2
                ;;
              --service-log-lines)
                SERVICE_LOG_LINES="$2"
                shift 2
                ;;
              --journald-log-lines)
                JOURNALD_LOG_LINES="$2"
                shift 2
                ;;
              --boot-log-lines)
                BOOT_LOG_LINES="$2"
                shift 2
                ;;
              --failed-file-limit)
                FAILED_FILE_LIMIT="$2"
                shift 2
                ;;
              --no-fss-test)
                RUN_FSS_TEST=0
                shift
                ;;
              --skip-dmesg)
                INCLUDE_DMESG=0
                shift
                ;;
              --help)
                usage
                exit 0
                ;;
              *)
                printf 'error: unknown option %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
              esac
            done

            require_root
            require_numeric "$SERVICE_LOG_LINES" "service-log-lines"
            require_numeric "$JOURNALD_LOG_LINES" "journald-log-lines"
            require_numeric "$BOOT_LOG_LINES" "boot-log-lines"
            require_numeric "$FAILED_FILE_LIMIT" "failed-file-limit"

            mkdir -p \
              "$OUT_DIR/config" \
              "$OUT_DIR/identity" \
              "$OUT_DIR/layout" \
              "$OUT_DIR/logs" \
              "$OUT_DIR/services" \
              "$OUT_DIR/summary" \
              "$OUT_DIR/verify"

            extract_exit_code() {
              local file="$1"

              awk -F= '/^__exit_code=/{code=$2} END{print code}' "$file"
            }

            payload_lines() {
              local file="$1"

              sed '/^#/d;/^$/d;/^__exit_code=/d' "$file"
            }

            extract_systemctl_field() {
              local file="$1"
              local field="$2"

              awk -F= -v field="$field" '$1 == field { value=$2 } END { print value }' "$file"
            }

            count_nonempty_lines() {
              local value="$1"

              printf '%s\n' "$value" | sed '/^$/d' | wc -l
            }

            quote_for_shell() {
              printf '%q' "$1"
            }

        is_sensitive_path() {
              case "$1" in
                */fss|*/verification-key|*/hardware-key|*/setup-output.txt)
                  return 0
                  ;;
              esac

              return 1
            }

            print_path_block() {
              local path="$1"

              printf '== %s ==\n' "$path"
              ls -ld "$path" 2>/dev/null || true

              if [ -d "$path" ]; then
                ls -lAh "$path" 2>/dev/null || true
                return 0
              fi

              if [ -L "$path" ] || [ -f "$path" ]; then
                if is_sensitive_path "$path"; then
                  echo "[contents redacted]"
                else
                  cat "$path" 2>/dev/null || true
                  echo
                fi
              fi
            }

            capture_shell() {
              local file="$1"
              local description="$2"
              local command="$3"
              local exit_code=0

              {
                printf '# collected_at=%s\n' "$(date -u +%FT%TZ)"
                printf '# command=%s\n\n' "$description"

                if bash -lc "$command"; then
                  exit_code=0
                else
                  exit_code=$?
                fi

                printf '\n__exit_code=%s\n' "$exit_code"
              } >"$file" 2>&1
            }

            discover_identity_files() {
              GHAF_HOSTNAME_FILE="$(
                fss_first_existing_path \
                  /run/ghaf-hostname \
                  /etc/common/ghaf/hostname \
                  /persist/common/ghaf/hostname \
                  /var/lib/ghaf/identity/hostname \
                  || true
              )"
              GHAF_ID_FILE="$(
                fss_first_existing_path \
                  /etc/common/ghaf/id \
                  /persist/common/ghaf/id \
                  /var/lib/ghaf/identity/id \
                  || true
              )"
              GHAF_UUID_FILE="$(
                fss_first_existing_path \
                  /etc/common/ghaf/uuid \
                  /persist/common/ghaf/uuid \
                  || true
              )"
              GHAF_DEVICE_ID_FILE="$(
                fss_first_existing_path \
                  /etc/common/device-id \
                  /persist/common/device-id \
                  || true
              )"

              if [ -n "$GHAF_HOSTNAME_FILE" ] && [ -r "$GHAF_HOSTNAME_FILE" ]; then
                GHAF_SHARED_HOSTNAME="$(cat "$GHAF_HOSTNAME_FILE")"
              fi
              if [ -n "$GHAF_ID_FILE" ] && [ -r "$GHAF_ID_FILE" ]; then
                GHAF_SHARED_ID="$(cat "$GHAF_ID_FILE")"
              fi
              if [ -n "$GHAF_UUID_FILE" ] && [ -r "$GHAF_UUID_FILE" ]; then
                GHAF_SHARED_UUID="$(cat "$GHAF_UUID_FILE")"
              fi
              if [ -n "$GHAF_DEVICE_ID_FILE" ] && [ -r "$GHAF_DEVICE_ID_FILE" ]; then
                GHAF_DEVICE_ID="$(cat "$GHAF_DEVICE_ID_FILE")"
              fi
            }

            discover_verify_key() {
              if [ -n "$FSS_VERIFY_KEY_PATH" ] && [ -e "$FSS_VERIFY_KEY_PATH" ]; then
                if [ -r "$FSS_VERIFY_KEY_PATH" ] && [ -s "$FSS_VERIFY_KEY_PATH" ]; then
                  VERIFY_KEY="$(cat "$FSS_VERIFY_KEY_PATH")"
                  VERIFY_KEY_BYTES=$(printf '%s' "$VERIFY_KEY" | wc -c)
                  VERIFY_KEY_STATE="readable"
                elif [ -s "$FSS_VERIFY_KEY_PATH" ]; then
                  VERIFY_KEY_STATE="unreadable"
                else
                  VERIFY_KEY_STATE="empty"
                fi
              else
                VERIFY_KEY_STATE="missing"
              fi
            }

            write_readme() {
              cat <<EOF | dedent_block >"$OUT_DIR/README.md"
        <!--
        SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
        SPDX-License-Identifier: Apache-2.0
        -->

        # FSS Debug Packet

        This directory was created by \`fss-debug\` on $(date -u +%FT%TZ).

        Contents:
        - \`summary/summary.md\`: top-level verdict and expected-vs-observed layout notes
        - \`identity/\`: runtime hostname, machine-id, Ghaf shared identity files, device-id
        - \`layout/\`: journal directory inventory, mounts, path resolution, file metadata
        - \`config/\`: journald config, unit definitions, audit rules
        - \`services/\`: systemd unit state for FSS, journald, recovery, and identity services
        - \`logs/\`: recent unit logs, journald logs, boot tail, optional dmesg excerpt
        - \`verify/\`: full verify output, active \`system.journal\` isolate, failed-file isolates, optional \`fss-test\`

        Sensitive material:
        - The verification key itself is never written to this packet.
        - Sealing key contents are not copied into this packet.
        - Hardware key contents are redacted if present.
    EOF
            }

            write_environment_file() {
              {
                printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                printf 'date_utc=%s\n' "$(date -u +%FT%TZ)"
                printf 'user=%s\n' "$(id -un 2>/dev/null || true)"
                printf 'uid=%s\n' "$(id -u 2>/dev/null || true)"
                printf 'runtime_hostname=%s\n' "$FSS_RUNTIME_HOSTNAME"
                printf 'kernel_hostname=%s\n' "$FSS_KERNEL_HOSTNAME"
                printf 'machine_id=%s\n' "$FSS_MACHINE_ID"
                printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
                printf 'uptime=%s\n' "$(uptime 2>/dev/null || true)"
                printf 'nixos_version=%s\n' "$(nixos-version 2>/dev/null || true)"
                printf 'current_system=%s\n' "$(readlink -f /run/current-system 2>/dev/null || true)"
                printf 'uname=%s\n' "$(uname -a 2>/dev/null || true)"
                echo
                echo '== /etc/os-release =='
                cat /etc/os-release 2>/dev/null || true
                echo
                echo '== systemctl --failed =='
                systemctl --failed --no-pager 2>/dev/null || true
                echo
                echo '== journalctl --list-boots =='
                journalctl --list-boots --no-pager 2>/dev/null || true
              } >"$OUT_DIR/identity/00-environment.txt" 2>&1
            }

            write_identity_file() {
              {
                printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                printf 'runtime_hostname=%s\n' "$FSS_RUNTIME_HOSTNAME"
                printf 'kernel_hostname=%s\n' "$FSS_KERNEL_HOSTNAME"
                printf 'ghaf_env_hostname=%s\n' "''${GHAF_HOSTNAME:-}"
                printf 'ghaf_env_hostname_file=%s\n' "''${GHAF_HOSTNAME_FILE:-}"
                printf 'machine_id=%s\n' "$FSS_MACHINE_ID"
                printf 'shared_hostname_file=%s\n' "$GHAF_HOSTNAME_FILE"
                printf 'shared_hostname=%s\n' "$GHAF_SHARED_HOSTNAME"
                printf 'shared_id_file=%s\n' "$GHAF_ID_FILE"
                printf 'shared_id=%s\n' "$GHAF_SHARED_ID"
                printf 'shared_uuid_file=%s\n' "$GHAF_UUID_FILE"
                printf 'shared_uuid=%s\n' "$GHAF_SHARED_UUID"
                printf 'device_id_file=%s\n' "$GHAF_DEVICE_ID_FILE"
                printf 'device_id=%s\n' "$GHAF_DEVICE_ID"
                echo

                for path in \
                  /run/ghaf-hostname \
                  /var/lib/ghaf/identity \
                  /var/lib/ghaf/identity/hostname \
                  /var/lib/ghaf/identity/id \
                  /var/lib/ghaf/identity/hardware-key \
                  /persist/common/ghaf \
                  /persist/common/ghaf/hostname \
                  /persist/common/ghaf/id \
                  /persist/common/ghaf/uuid \
                  /persist/common/device-id \
                  /etc/common/ghaf \
                  /etc/common/ghaf/hostname \
                  /etc/common/ghaf/id \
                  /etc/common/ghaf/uuid \
                  /etc/common/device-id; do
                  if [ -e "$path" ]; then
                    print_path_block "$path"
                    echo
                  fi
                done
              } >"$OUT_DIR/identity/01-identity-files.txt" 2>&1
            }

            write_host_vm_machine_ids() {
              if [ -d /persist/storagevm ]; then
                capture_shell \
                  "$OUT_DIR/identity/02-host-vm-machine-ids.txt" \
                  "find /persist/storagevm -maxdepth 3 -path '*/etc/machine-id'" \
                  "find /persist/storagevm -maxdepth 3 -path '*/etc/machine-id' -print | sort | while read -r path; do echo \"== \$path ==\"; cat \"\$path\"; echo; done"
              fi
            }

            write_layout_file() {
              local expected_key_root="unknown"
              local expected_identity_note="unknown"
              local identity_note=""

              case "$FSS_COMPONENT_SCOPE" in
                host)
                  expected_key_root="/persist/common/journal-fss/<component>"
                  expected_identity_note="host identity is generated under /var/lib/ghaf/identity and shared via /persist/common/ghaf"
                  ;;
                vm)
                  expected_key_root="/etc/common/journal-fss/<component>"
                  expected_identity_note="VMs normally read shared identity from /etc/common/ghaf; runtime hostname may still remain static"
                  ;;
              esac

              if [ -n "$GHAF_SHARED_HOSTNAME" ] && [ -n "$FSS_RUNTIME_HOSTNAME" ] && [ "$GHAF_SHARED_HOSTNAME" != "$FSS_RUNTIME_HOSTNAME" ]; then
                identity_note="shared dynamic hostname differs from runtime hostname; this is expected for VMs that import Ghaf identity without replacing the kernel hostname"
              fi

              {
                printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                cat <<EOF | dedent_block
        Expected FSS layout:
        - sealing key path: /var/log/journal/<machine-id>/fss (or /run/log/journal/<machine-id>/fss for volatile storage)
        - verification key root: ''${expected_key_root}
        - layout authority: /var/log/journal/<machine-id>/fss-config when present
        - identity note: ''${expected_identity_note}

        Observed runtime layout:
        - component_scope: ''${FSS_COMPONENT_SCOPE}
        - component_name: ''${FSS_COMPONENT_NAME}
        - runtime_hostname: ''${FSS_RUNTIME_HOSTNAME}
        - kernel_hostname: ''${FSS_KERNEL_HOSTNAME}
        - machine_id: ''${FSS_MACHINE_ID}
        - journal_dir: ''${FSS_JOURNAL_DIR}
        - active_system_journal: ''${FSS_ACTIVE_SYSTEM_JOURNAL}
        - sealing_key_path: ''${FSS_SEALING_KEY_PATH}
        - fss_config_path: ''${FSS_FSS_CONFIG_PATH}
        - fss_rotated_path: ''${FSS_FSS_ROTATED_PATH}
        - key_dir_source: ''${FSS_KEY_DIR_SOURCE}
        - key_dir: ''${FSS_KEY_DIR}
        - verification_key_path: ''${FSS_VERIFY_KEY_PATH}
        - initialized_path: ''${FSS_INITIALIZED_PATH}
        - shared_hostname: ''${GHAF_SHARED_HOSTNAME}
        - shared_id: ''${GHAF_SHARED_ID}
        - shared_uuid: ''${GHAF_SHARED_UUID}
        - device_id: ''${GHAF_DEVICE_ID}
    EOF
                if [ -n "$identity_note" ]; then
                  printf -- "- identity_observation: %s\n" "$identity_note"
                fi
                if [ -n "$FSS_KEY_DIR_CANDIDATES" ]; then
                  echo
                  echo 'Hostname fallback candidates:'
                  printf '%s\n' "$FSS_KEY_DIR_CANDIDATES"
                fi
              } >"$OUT_DIR/layout/00-runtime-layout.txt" 2>&1
            }

            write_journal_inventory() {
              {
                printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                printf 'journal_dir=%s\n' "$FSS_JOURNAL_DIR"
                printf 'active_system_journal=%s\n' "$FSS_ACTIVE_SYSTEM_JOURNAL"
                printf 'sealing_key_path=%s\n' "$FSS_SEALING_KEY_PATH"
                printf 'fss_config_path=%s\n' "$FSS_FSS_CONFIG_PATH"
                printf 'key_dir=%s\n' "$FSS_KEY_DIR"
                echo

                for path in \
                  /var/log/journal \
                  "/var/log/journal/$FSS_MACHINE_ID" \
                  "/run/log/journal/$FSS_MACHINE_ID" \
                  "$FSS_SEALING_KEY_PATH" \
                  "$FSS_FSS_CONFIG_PATH" \
                  "$FSS_FSS_ROTATED_PATH" \
                  "$FSS_VERIFY_KEY_PATH" \
                  "$FSS_INITIALIZED_PATH"; do
                  if [ -n "$path" ] && [ -e "$path" ]; then
                    print_path_block "$path"
                    echo
                  fi
                done

                if [ -n "$FSS_JOURNAL_DIR" ] && [ -d "$FSS_JOURNAL_DIR" ]; then
                  echo '== journal file inventory =='
                  find "$FSS_JOURNAL_DIR" -maxdepth 1 -type f | sort | while read -r path; do
                    stat -c '%n|size=%s|mode=%a|uid=%u|gid=%g|mtime=%y' "$path" 2>/dev/null || true
                  done
                  echo
                  echo '== journalctl --disk-usage =='
                  journalctl --disk-usage 2>/dev/null || true
                fi

                if [ -n "$FSS_ACTIVE_SYSTEM_JOURNAL" ] && [ -f "$FSS_ACTIVE_SYSTEM_JOURNAL" ]; then
                  echo
                  echo '== active system journal digest =='
                  sha256sum "$FSS_ACTIVE_SYSTEM_JOURNAL" 2>/dev/null || true
                  stat -c '%n|size=%s|mode=%a|uid=%u|gid=%g|mtime=%y' "$FSS_ACTIVE_SYSTEM_JOURNAL" 2>/dev/null || true
                fi
              } >"$OUT_DIR/layout/01-journal-inventory.txt" 2>&1
            }

            collect_mounted_paths() {
              capture_shell \
                "$OUT_DIR/layout/02-mounts.txt" \
                "findmnt /var/log/journal /run/log/journal /persist/common /etc/common /var/lib/ghaf/identity" \
                "findmnt /var/log/journal /run/log/journal /persist/common /etc/common /var/lib/ghaf/identity 2>/dev/null || true; echo; findmnt -R /var/log/journal 2>/dev/null || true"
            }

            collect_unit_files() {
              capture_shell \
                "$OUT_DIR/config/00-journald-config.txt" \
                "systemd-analyze cat-config systemd/journald.conf" \
                "systemd-analyze cat-config systemd/journald.conf 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/config/01-unit-definitions.txt" \
                "systemctl cat journal-fss-setup.service journal-fss-verify.service journal-fss-verify.timer systemd-journald.service ghaf-dynamic-hostname.service set-dynamic-hostname.service ghaf-clock-jump-watcher.service ghaf-journal-alloy-recover.service alloy.service" \
                "systemctl cat journal-fss-setup.service journal-fss-verify.service journal-fss-verify.timer systemd-journald.service ghaf-dynamic-hostname.service set-dynamic-hostname.service ghaf-clock-jump-watcher.service ghaf-journal-alloy-recover.service alloy.service 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/config/02-audit-rules.txt" \
                "auditctl -l" \
                "if command -v auditctl >/dev/null 2>&1; then auditctl -l 2>/dev/null || true; else echo 'auditctl not available'; fi"
            }

            collect_services() {
              capture_shell \
                "$OUT_DIR/services/00-journal-fss-setup.show.txt" \
                "systemctl show journal-fss-setup.service" \
                "systemctl show journal-fss-setup.service -p Id,Names,LoadState,UnitFileState,ActiveState,SubState,Result,ConditionResult,ExecMainStatus,ExecMainCode,FragmentPath --no-pager 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/01-journal-fss-setup.status.txt" \
                "systemctl status journal-fss-setup.service" \
                "systemctl status --no-pager journal-fss-setup.service 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/02-journal-fss-verify.show.txt" \
                "systemctl show journal-fss-verify.service" \
                "systemctl show journal-fss-verify.service -p Id,Names,LoadState,UnitFileState,ActiveState,SubState,Result,ConditionResult,ExecMainStatus,ExecMainCode,FragmentPath --no-pager 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/03-journal-fss-verify.status.txt" \
                "systemctl status journal-fss-verify.service" \
                "systemctl status --no-pager journal-fss-verify.service 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/04-journal-fss-verify.timer.show.txt" \
                "systemctl show journal-fss-verify.timer" \
                "systemctl show journal-fss-verify.timer -p Id,Names,LoadState,UnitFileState,ActiveState,SubState,Result,NextElapseUSecRealtime,LastTriggerUSec,FragmentPath --no-pager 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/05-journal-fss-verify.timer.status.txt" \
                "systemctl status journal-fss-verify.timer" \
                "systemctl status --no-pager journal-fss-verify.timer 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/06-systemd-journald.show.txt" \
                "systemctl show systemd-journald.service" \
                "systemctl show systemd-journald.service -p Id,Names,LoadState,UnitFileState,ActiveState,SubState,Result,ExecMainStatus,ExecMainCode,FragmentPath --no-pager 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/07-systemd-journald.status.txt" \
                "systemctl status systemd-journald.service" \
                "systemctl status --no-pager systemd-journald.service 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/services/08-optional-services.txt" \
                "systemctl status ghaf-dynamic-hostname.service set-dynamic-hostname.service ghaf-clock-jump-watcher.service ghaf-journal-alloy-recover.service alloy.service" \
                "for unit in ghaf-dynamic-hostname.service set-dynamic-hostname.service ghaf-clock-jump-watcher.service ghaf-journal-alloy-recover.service alloy.service; do echo \"== \$unit ==\"; systemctl show \"\$unit\" -p LoadState,UnitFileState,ActiveState,SubState,Result,ExecMainStatus,ExecMainCode,FragmentPath --no-pager 2>/dev/null || true; systemctl status --no-pager \"\$unit\" 2>/dev/null || true; echo; done"
            }

            collect_logs() {
              capture_shell \
                "$OUT_DIR/logs/00-journal-fss-setup.log.txt" \
                "journalctl -u journal-fss-setup.service -b -n $SERVICE_LOG_LINES" \
                "journalctl -u journal-fss-setup.service --no-pager -b -n $SERVICE_LOG_LINES 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/logs/01-journal-fss-verify.log.txt" \
                "journalctl -u journal-fss-verify.service -b -n $SERVICE_LOG_LINES" \
                "journalctl -u journal-fss-verify.service --no-pager -b -n $SERVICE_LOG_LINES 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/logs/02-systemd-journald.log.txt" \
                "journalctl -u systemd-journald.service -b -n $JOURNALD_LOG_LINES" \
                "journalctl -u systemd-journald --no-pager -b -n $JOURNALD_LOG_LINES 2>/dev/null || true"
              capture_shell \
                "$OUT_DIR/logs/03-systemd-journald-alerts.txt" \
                "journalctl -u systemd-journald.service -b | grep alert patterns" \
                "journalctl -u systemd-journald --no-pager -b -n $JOURNALD_LOG_LINES 2>/dev/null | grep -Ei 'corrupt|unclean|renam|I/O|Bad message|Time jumped backwards|rotating|flush runtime journal' || true"
              capture_shell \
                "$OUT_DIR/logs/04-boot-tail.txt" \
                "journalctl -b -n $BOOT_LOG_LINES" \
                "journalctl -b --no-pager -n $BOOT_LOG_LINES 2>/dev/null || true"

              if [ "$INCLUDE_DMESG" -eq 1 ]; then
                capture_shell \
                  "$OUT_DIR/logs/05-dmesg-alerts.txt" \
                  "dmesg | grep storage and corruption patterns" \
                  "dmesg 2>/dev/null | grep -Ei 'I/O|ext4|btrfs|blk|nvme|virtio|corrupt|error|journal' || true"
              else
                {
                  printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                  echo 'dmesg capture skipped'
                  printf '\n__exit_code=0\n'
                } >"$OUT_DIR/logs/05-dmesg-alerts.txt"
              fi
            }

            collect_verification() {
              local quoted_key=""
              local quoted_system_journal=""

              if [ "$VERIFY_KEY_STATE" = "readable" ]; then
                quoted_key="$(quote_for_shell "$VERIFY_KEY")"
                capture_shell \
                  "$OUT_DIR/verify/00-full.txt" \
                  "journalctl --verify --verify-key=<redacted>" \
                  "journalctl --verify --verify-key=$quoted_key"

                if [ -n "$FSS_ACTIVE_SYSTEM_JOURNAL" ] && [ -f "$FSS_ACTIVE_SYSTEM_JOURNAL" ]; then
                  quoted_system_journal="$(quote_for_shell "$FSS_ACTIVE_SYSTEM_JOURNAL")"
                  capture_shell \
                    "$OUT_DIR/verify/01-active-system.txt" \
                    "journalctl --verify --verify-key=<redacted> --file=$FSS_ACTIVE_SYSTEM_JOURNAL" \
                    "journalctl --verify --verify-key=$quoted_key --file=$quoted_system_journal"
                else
                  {
                    printf '# collected_at=%s\n' "$(date -u +%FT%TZ)"
                    printf '# command=%s\n\n' 'journalctl --verify --verify-key=<redacted> --file=<active system journal>'
                    echo 'ERROR: active system.journal not found'
                    printf '\n__exit_code=3\n'
                  } >"$OUT_DIR/verify/01-active-system.txt"
                fi
              else
                {
                  printf '# collected_at=%s\n' "$(date -u +%FT%TZ)"
                  printf '# command=%s\n\n' 'journalctl --verify --verify-key=<redacted>'
                  printf 'ERROR: verification key state is %s\n' "$VERIFY_KEY_STATE"
                  printf '\n__exit_code=2\n'
                } >"$OUT_DIR/verify/00-full.txt"
                cp "$OUT_DIR/verify/00-full.txt" "$OUT_DIR/verify/01-active-system.txt"
              fi
            }

            write_failed_file_report() {
              local file="$OUT_DIR/verify/02-failed-files.txt"
              local path=""
              local count=0
              local -a failed_files=()

              if [ "$VERIFY_KEY_STATE" = "readable" ]; then
                while IFS= read -r path; do
                  if [ -n "$path" ]; then
                    failed_files+=("$path")
                  fi
                done < <(
                  payload_lines "$OUT_DIR/verify/00-full.txt" \
                    | awk '/^FAIL: / { print $2 }' \
                    | awk '!seen[$0]++' \
                    | head -n "$FAILED_FILE_LIMIT"
                )
              fi

              {
                printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
                printf 'failed_file_limit=%s\n' "$FAILED_FILE_LIMIT"
                printf 'verify_key_state=%s\n' "$VERIFY_KEY_STATE"
                printf 'failed_file_count=%s\n' "''${#failed_files[@]}"
                echo

                if [ "$VERIFY_KEY_STATE" != "readable" ]; then
                  echo 'Verification key is not readable; skipping failed-file re-verification.'
                elif [ "''${#failed_files[@]}" -eq 0 ]; then
                  echo 'No failed files were reported by the full verify output.'
                else
                  for path in "''${failed_files[@]}"; do
                    count=$((count + 1))
                    printf '== failed_file_%02d: %s ==\n' "$count" "$path"
                    if [ -e "$path" ]; then
                      stat -c '%n|size=%s|mode=%a|uid=%u|gid=%g|mtime=%y' "$path" 2>/dev/null || true
                      sha256sum "$path" 2>/dev/null || true
                      journalctl --verify --verify-key="$VERIFY_KEY" --file="$path" 2>&1 || true
                    else
                      echo 'File no longer exists'
                    fi
                    echo
                  done
                fi
              } >"$file" 2>&1
            }

            collect_fss_test() {
              if [ "$RUN_FSS_TEST" -eq 1 ] && command -v fss-test >/dev/null 2>&1; then
                capture_shell \
                  "$OUT_DIR/verify/03-fss-test.txt" \
                  "fss-test" \
                  "fss-test"
              else
                {
                  printf '# collected_at=%s\n' "$(date -u +%FT%TZ)"
                  printf '# command=%s\n\n' 'fss-test'
                  if [ "$RUN_FSS_TEST" -eq 0 ]; then
                    echo 'Skipped by --no-fss-test'
                  else
                    echo 'fss-test is not installed'
                  fi
                  printf '\n__exit_code=0\n'
                } >"$OUT_DIR/verify/03-fss-test.txt"
              fi
            }

            write_summary() {
              local verify_output
              local verify_tags=""
              local verify_status="clean"
              local verify_full_exit=""
              local verify_system_exit=""
              local verify_service_result=""
              local verify_service_exit=""
              local setup_result=""
              local setup_state=""
              local timer_state=""
              local timer_next=""
              local fss_test_exit=""
              local journald_alert_count=0
              local active_count=0
              local archived_count=0
              local user_count=0
              local temp_count=0
              local other_count=0
              local filesystem_restriction=0
              local policy_outcome="PASS"
              local mismatch_note=""
              local next_actions=""

              verify_output="$(payload_lines "$OUT_DIR/verify/00-full.txt")"
              verify_tags="$(fss_reason_tags_from_output "$verify_output")"
              fss_classify_verify_output "$verify_output"
              verify_tags="$(fss_classification_tags "$verify_tags")"
              verify_full_exit="$(extract_exit_code "$OUT_DIR/verify/00-full.txt")"
              verify_system_exit="$(extract_exit_code "$OUT_DIR/verify/01-active-system.txt")"
              verify_service_result="$(extract_systemctl_field "$OUT_DIR/services/02-journal-fss-verify.show.txt" "Result")"
              verify_service_exit="$(extract_systemctl_field "$OUT_DIR/services/02-journal-fss-verify.show.txt" "ExecMainStatus")"
              setup_result="$(extract_systemctl_field "$OUT_DIR/services/00-journal-fss-setup.show.txt" "Result")"
              setup_state="$(extract_systemctl_field "$OUT_DIR/services/00-journal-fss-setup.show.txt" "ActiveState")"
              timer_state="$(extract_systemctl_field "$OUT_DIR/services/04-journal-fss-verify.timer.show.txt" "ActiveState")"
              timer_next="$(extract_systemctl_field "$OUT_DIR/services/04-journal-fss-verify.timer.show.txt" "NextElapseUSecRealtime")"
              fss_test_exit="$(extract_exit_code "$OUT_DIR/verify/03-fss-test.txt")"
              journald_alert_count="$(payload_lines "$OUT_DIR/logs/03-systemd-journald-alerts.txt" | sed '/^$/d' | wc -l)"

              active_count="$(count_nonempty_lines "$FSS_ACTIVE_SYSTEM_FAILURES")"
              archived_count="$(count_nonempty_lines "$FSS_ARCHIVED_SYSTEM_FAILURES")"
              user_count="$(count_nonempty_lines "$FSS_USER_FAILURES")"
              temp_count="$(count_nonempty_lines "$FSS_TEMP_FAILURES")"
              other_count="$(count_nonempty_lines "$FSS_OTHER_FAILURES")"
              filesystem_restriction="$FSS_FILESYSTEM_RESTRICTION"

              if [ "$FSS_KEY_PARSE_ERROR" -eq 1 ] || [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]; then
                verify_status="key_defect"
                policy_outcome="FAIL"
              elif [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] || [ -n "$FSS_OTHER_FAILURES" ]; then
                verify_status="active_failure"
                policy_outcome="FAIL"
              elif [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ] || [ -n "$FSS_USER_FAILURES" ]; then
                verify_status="warning_only"
                policy_outcome="WARN"
              elif [ -n "$FSS_TEMP_FAILURES" ]; then
                verify_status="temp_only"
                policy_outcome="PASS"
              elif [ "$filesystem_restriction" -eq 1 ]; then
                verify_status="filesystem_restriction"
                policy_outcome="WARN"
              elif [ "$verify_full_exit" != "0" ]; then
                verify_status="verify_nonzero_no_fail"
                policy_outcome="WARN"
              fi

              if [ "$verify_status" = "active_failure" ] && [ "$active_count" -eq 0 ] && [ "$other_count" -gt 0 ]; then
                mismatch_note="blocking failure came from unclassified FAIL records while the active system journal isolate did not report a failure"
              elif [ "$verify_status" = "warning_only" ] && [ "$verify_service_result" = "failed" ]; then
                mismatch_note="service failed even though verification classified as warning-only"
              elif [ "$verify_status" = "clean" ] && [ "$verify_service_result" = "failed" ]; then
                mismatch_note="service failed even though verification classified as clean"
              fi

              case "$verify_status" in
                active_failure)
                  if [ "$active_count" -gt 0 ]; then
                    next_actions="Preserve the active system.journal, inspect systemd-journald and dmesg for storage or recovery issues, and compare active journal corruption with archived failures."
                  else
                    next_actions="Inspect the unclassified FAIL records in the full verify output. If they are diagnostic context rather than real file failures, update the classifier; otherwise treat them as a new critical failure class."
                  fi
                  ;;
                key_defect)
                  next_actions="Inspect verification-key extraction, fss-config, and key permissions. Compare the configured key dir with the path written by journal-fss-setup."
                  ;;
                warning_only)
                  next_actions="Active system journal is currently clean. Treat remaining failures as archived/user residuals and correlate them with rotation or recovery history."
                  ;;
                temp_only)
                  next_actions="Only temporary journal files failed. Re-check after journal rotation and confirm the active system journal remains clean."
                  ;;
                clean)
                  next_actions="No verification failures detected. If the incident is intermittent, run this tool again after the next journal-fss-verify.timer trigger."
                  ;;
                *)
                  next_actions="Review the raw verification output for non-classified errors."
                  ;;
              esac

              cat <<EOF | dedent_block >"$OUT_DIR/summary/summary.md"
        <!--
        SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
        SPDX-License-Identifier: Apache-2.0
        -->

        # FSS Debug Summary

        ## Verdict

        - classification: ''${verify_status}
        - policy_outcome: ''${policy_outcome}
        - verify_tags: ''${verify_tags:-none}
        - verify_full_exit: ''${verify_full_exit}
        - verify_active_system_exit: ''${verify_system_exit}
        - service_result: ''${verify_service_result:-unknown}
        - service_exec_main_status: ''${verify_service_exit:-unknown}
        - fss_test_exit: ''${fss_test_exit:-unknown}

        ## Runtime Layout

        - component_scope: ''${FSS_COMPONENT_SCOPE}
        - component_name: ''${FSS_COMPONENT_NAME}
        - runtime_hostname: ''${FSS_RUNTIME_HOSTNAME}
        - kernel_hostname: ''${FSS_KERNEL_HOSTNAME}
        - shared_dynamic_hostname: ''${GHAF_SHARED_HOSTNAME}
        - shared_numeric_id: ''${GHAF_SHARED_ID}
        - shared_uuid: ''${GHAF_SHARED_UUID}
        - device_id: ''${GHAF_DEVICE_ID}
        - machine_id: ''${FSS_MACHINE_ID}
        - journal_dir: ''${FSS_JOURNAL_DIR}
        - active_system_journal: ''${FSS_ACTIVE_SYSTEM_JOURNAL}
        - sealing_key_path: ''${FSS_SEALING_KEY_PATH}
        - fss_config_path: ''${FSS_FSS_CONFIG_PATH}
        - key_dir_source: ''${FSS_KEY_DIR_SOURCE}
        - key_dir: ''${FSS_KEY_DIR}
        - verification_key_path: ''${FSS_VERIFY_KEY_PATH}
        - verification_key_state: ''${VERIFY_KEY_STATE}
        - verification_key_bytes: ''${VERIFY_KEY_BYTES}
        - initialized_path: ''${FSS_INITIALIZED_PATH}

        ## Service State

        - journal_fss_setup_active_state: ''${setup_state:-unknown}
        - journal_fss_setup_result: ''${setup_result:-unknown}
        - journal_fss_verify_timer_active_state: ''${timer_state:-unknown}
        - journal_fss_verify_timer_next: ''${timer_next:-unknown}
        - journald_alert_count: ''${journald_alert_count}
        - filesystem_restriction_detected: ''${filesystem_restriction}

        ## Failure Buckets

        - active_system_failures: ''${active_count}
        - archived_system_failures: ''${archived_count}
        - user_journal_failures: ''${user_count}
        - temp_failures: ''${temp_count}
        - other_failures: ''${other_count}
    EOF

              if [ -n "$mismatch_note" ]; then
                printf '\n## Policy Mismatch\n\n- %s\n' "$mismatch_note" >>"$OUT_DIR/summary/summary.md"
              fi

              cat <<EOF | dedent_block >>"$OUT_DIR/summary/summary.md"

        ## Notes

        - FSS sealing keys are expected under \`/var/log/journal/<machine-id>/fss\` or \`/run/log/journal/<machine-id>/fss\`.
        - FSS verification keys are expected under \`/persist/common/journal-fss/<component>\` on host and \`/etc/common/journal-fss/<component>\` in VMs.
        - The authoritative runtime mapping is \`/var/log/journal/<machine-id>/fss-config\` when present.
        - Dynamic Ghaf identity files (\`hostname\`, \`id\`, \`uuid\`, \`device-id\`) describe hardware identity and may differ from the component name used for FSS key storage.

        ## Suggested Next Action

        - ''${next_actions}

        ## Key Files

        - runtime layout: ''${OUT_DIR}/layout/00-runtime-layout.txt
        - journal inventory: ''${OUT_DIR}/layout/01-journal-inventory.txt
        - verify full: ''${OUT_DIR}/verify/00-full.txt
        - verify active system: ''${OUT_DIR}/verify/01-active-system.txt
        - failed-file isolates: ''${OUT_DIR}/verify/02-failed-files.txt
        - verify service logs: ''${OUT_DIR}/logs/01-journal-fss-verify.log.txt
        - journald alerts: ''${OUT_DIR}/logs/03-systemd-journald-alerts.txt
        - journald config: ''${OUT_DIR}/config/00-journald-config.txt
    EOF
            }

            fss_discover_runtime_layout
            discover_identity_files
            discover_verify_key

            log "writing debug packet to $OUT_DIR"
            write_readme
            write_environment_file
            write_identity_file
            write_host_vm_machine_ids
            write_layout_file
            write_journal_inventory
            collect_mounted_paths
            collect_unit_files
            collect_services
            collect_logs
            collect_verification
            write_failed_file_report
            collect_fss_test
            write_summary

            log "summary: $OUT_DIR/summary/summary.md"
            log "debug packet complete"
  '';
}
