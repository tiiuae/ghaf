#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -euo pipefail

COMMAND="${1:-help}"
if [ $# -gt 0 ]; then
  shift
fi

SESSION_DIR=""
LABEL=""
FROM_LABEL=""
TO_LABEL=""
VM_NAME="gui-vm"
SERVICE_LOG_LINES=800
JOURNALD_LOG_LINES=800
BOOT_LOG_LINES=800
RUN_FSS_TEST=1
INCLUDE_DMESG=1

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2
}

dedent_block() {
  sed 's/^    //'
}

usage() {
  cat <<'EOF' | dedent_block
    Usage: fss-rootcause <command> [options]

    Coordinate a repeatable FSS root-cause workflow around fss-debug packets.

    Commands:
      capture-guest   Capture a labeled guest checkpoint using fss-debug
      capture-host    Capture host-side microvm and power-management context for a VM
      compare         Compare two guest checkpoints from the same session
      help            Show this help

    Shared options:
      --session-dir <path>           Session root (default: /var/tmp/fss-rootcause-<UTC>)
      --service-log-lines <n>        Unit log lines to capture (default: 800)
      --journald-log-lines <n>       journald log lines for guest capture (default: 800)
      --boot-log-lines <n>           Boot/power log lines to capture (default: 800)
      --skip-dmesg                   Skip dmesg capture in guest/host snapshots
      --no-fss-test                  Skip fss-test during guest capture

    capture-guest options:
      --label <name>                 Required checkpoint label (for example: pre-idle)

    capture-host options:
      --label <name>                 Required checkpoint label
      --vm-name <name>               VM name to inspect (default: gui-vm)

    compare options:
      --from <label>                 Required source guest checkpoint label
      --to <label>                   Required destination guest checkpoint label

    Suggested workflow:
      sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label pre-idle
      sleep 900
      sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label post-idle
      sudo systemctl suspend
      sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label post-suspend
      sudo fss-rootcause compare --session-dir /var/tmp/gui-rootcause --from pre-idle --to post-idle
      sudo fss-rootcause compare --session-dir /var/tmp/gui-rootcause --from post-idle --to post-suspend

      On the host, capture matching VM lifecycle context:
      sudo fss-rootcause capture-host --session-dir /var/tmp/gui-rootcause --vm-name gui-vm --label post-suspend
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'error: fss-rootcause must be run as root\n' >&2
    exit 2
  fi
}

require_nonempty() {
  local value="$1"
  local label="$2"

  if [ -z "$value" ]; then
    printf 'error: %s is required\n' "$label" >&2
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

ensure_session_dir() {
  if [ -z "$SESSION_DIR" ]; then
    SESSION_DIR="/var/tmp/fss-rootcause-$(date -u +%Y%m%dT%H%M%SZ)"
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

extract_summary_field() {
  local file="$1"
  local key="$2"

  awk -F': ' -v needle="- ${key}" '$1 == needle { value=$2 } END { print value }' "$file"
}

failed_paths() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 0
  fi

  sed -n 's/^== failed_file_[0-9][0-9]*: \(.*\) ==$/\1/p' "$file" | sort -u
}

compare_text() {
  local lhs="$1"
  local rhs="$2"
  local out="$3"
  local status=0

  if [ ! -e "$lhs" ] || [ ! -e "$rhs" ]; then
    {
      printf 'Missing comparison input.\n'
      printf 'lhs=%s\n' "$lhs"
      printf 'rhs=%s\n' "$rhs"
    } >"$out"
    return 0
  fi

  if diff -u "$lhs" "$rhs" >"$out"; then
    return 0
  fi

  status=$?
  if [ "$status" -ne 1 ]; then
    return "$status"
  fi
}

resolve_vm_unit() {
  local vm_name="$1"
  local unit=""

  unit="$(
    systemctl list-units --all --plain --no-legend "microvm*${vm_name}*" 2>/dev/null |
      awk 'NR == 1 { print $1 }'
  )"

  if [ -z "$unit" ]; then
    unit="$(
      systemctl list-unit-files --plain --no-legend "microvm*${vm_name}*" 2>/dev/null |
        awk 'NR == 1 { print $1 }'
    )"
  fi

  if [ -z "$unit" ]; then
    printf 'error: could not resolve a microvm unit for %s\n' "$vm_name" >&2
    exit 3
  fi

  printf '%s\n' "$unit"
}

capture_guest() {
  local checkpoint_dir=""
  local packet_dir=""
  local summary_file=""
  local classification=""
  local policy_outcome=""
  local active_failures=""
  local archived_failures=""
  local user_failures=""
  local temp_failures=""

  require_root
  require_nonempty "$LABEL" "label"
  require_numeric "$SERVICE_LOG_LINES" "service-log-lines"
  require_numeric "$JOURNALD_LOG_LINES" "journald-log-lines"
  require_numeric "$BOOT_LOG_LINES" "boot-log-lines"
  ensure_session_dir

  checkpoint_dir="$SESSION_DIR/guest/$LABEL"
  packet_dir="$checkpoint_dir/fss-debug"
  summary_file="$checkpoint_dir/checkpoint.md"

  mkdir -p "$checkpoint_dir"

  log "capturing guest checkpoint '$LABEL' into $packet_dir"

  if [ "$RUN_FSS_TEST" -eq 1 ]; then
    if [ "$INCLUDE_DMESG" -eq 1 ]; then
      fss-debug \
        --out-dir "$packet_dir" \
        --service-log-lines "$SERVICE_LOG_LINES" \
        --journald-log-lines "$JOURNALD_LOG_LINES" \
        --boot-log-lines "$BOOT_LOG_LINES"
    else
      fss-debug \
        --out-dir "$packet_dir" \
        --service-log-lines "$SERVICE_LOG_LINES" \
        --journald-log-lines "$JOURNALD_LOG_LINES" \
        --boot-log-lines "$BOOT_LOG_LINES" \
        --skip-dmesg
    fi
  else
    if [ "$INCLUDE_DMESG" -eq 1 ]; then
      fss-debug \
        --out-dir "$packet_dir" \
        --service-log-lines "$SERVICE_LOG_LINES" \
        --journald-log-lines "$JOURNALD_LOG_LINES" \
        --boot-log-lines "$BOOT_LOG_LINES" \
        --no-fss-test
    else
      fss-debug \
        --out-dir "$packet_dir" \
        --service-log-lines "$SERVICE_LOG_LINES" \
        --journald-log-lines "$JOURNALD_LOG_LINES" \
        --boot-log-lines "$BOOT_LOG_LINES" \
        --no-fss-test \
        --skip-dmesg
    fi
  fi

  classification="$(extract_summary_field "$packet_dir/summary/summary.md" "classification")"
  policy_outcome="$(extract_summary_field "$packet_dir/summary/summary.md" "policy_outcome")"
  active_failures="$(extract_summary_field "$packet_dir/summary/summary.md" "active_system_failures")"
  archived_failures="$(extract_summary_field "$packet_dir/summary/summary.md" "archived_system_failures")"
  user_failures="$(extract_summary_field "$packet_dir/summary/summary.md" "user_journal_failures")"
  temp_failures="$(extract_summary_field "$packet_dir/summary/summary.md" "temp_failures")"

  cat <<EOF >"$summary_file"
<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# FSS Root-Cause Guest Checkpoint

- label: $LABEL
- collected_at: $(date -u +%FT%TZ)
- session_dir: $SESSION_DIR
- packet_dir: $packet_dir
- classification: ${classification:-unknown}
- policy_outcome: ${policy_outcome:-unknown}
- active_system_failures: ${active_failures:-unknown}
- archived_system_failures: ${archived_failures:-unknown}
- user_journal_failures: ${user_failures:-unknown}
- temp_failures: ${temp_failures:-unknown}
- summary_file: $packet_dir/summary/summary.md
EOF

  log "guest checkpoint summary: $summary_file"
}

capture_host() {
  local out_dir=""
  local unit=""
  local summary_file=""

  require_root
  require_nonempty "$LABEL" "label"
  require_nonempty "$VM_NAME" "vm-name"
  require_numeric "$SERVICE_LOG_LINES" "service-log-lines"
  require_numeric "$BOOT_LOG_LINES" "boot-log-lines"
  ensure_session_dir

  out_dir="$SESSION_DIR/host/$VM_NAME/$LABEL"
  summary_file="$out_dir/summary.md"
  mkdir -p "$out_dir"

  unit="$(resolve_vm_unit "$VM_NAME")"

  log "capturing host checkpoint '$LABEL' for $VM_NAME via unit $unit"

  capture_shell \
    "$out_dir/00-environment.txt" \
    "date, hostname, failed units" \
    "date -u; echo; hostname; echo; systemctl --failed --no-pager 2>/dev/null || true"
  capture_shell \
    "$out_dir/01-unit-discovery.txt" \
    "systemctl list-units/list-unit-files microvm*${VM_NAME}*" \
    "systemctl list-units --all --plain --no-legend 'microvm*${VM_NAME}*' 2>/dev/null || true; echo; systemctl list-unit-files --plain --no-legend 'microvm*${VM_NAME}*' 2>/dev/null || true"
  capture_shell \
    "$out_dir/02-unit-definition.txt" \
    "systemctl cat $unit" \
    "systemctl cat '$unit' 2>/dev/null || true"
  capture_shell \
    "$out_dir/03-unit-show.txt" \
    "systemctl show $unit" \
    "systemctl show '$unit' --no-pager 2>/dev/null || true"
  capture_shell \
    "$out_dir/04-unit-status.txt" \
    "systemctl status $unit" \
    "systemctl status --no-pager '$unit' 2>/dev/null || true"
  capture_shell \
    "$out_dir/05-unit-log.txt" \
    "journalctl -u $unit -b -n $SERVICE_LOG_LINES" \
    "journalctl -u '$unit' --no-pager -b -n $SERVICE_LOG_LINES 2>/dev/null || true"
  capture_shell \
    "$out_dir/06-systemd-logind.log.txt" \
    "journalctl -u systemd-logind.service -b -n $SERVICE_LOG_LINES" \
    "journalctl -u systemd-logind.service --no-pager -b -n $SERVICE_LOG_LINES 2>/dev/null || true"
  capture_shell \
    "$out_dir/07-systemd-suspend.log.txt" \
    "journalctl -u systemd-suspend.service -b -n $SERVICE_LOG_LINES" \
    "journalctl -u systemd-suspend.service --no-pager -b -n $SERVICE_LOG_LINES 2>/dev/null || true"
  capture_shell \
    "$out_dir/08-host-power-events.txt" \
    "journalctl -b | grep host power and microvm patterns" \
    "journalctl -b --no-pager 2>/dev/null | grep -Ei 'microvm|suspend|resume|sleep|hibernate|freeze|logind|power' | tail -n $BOOT_LOG_LINES || true"

  if [ "$INCLUDE_DMESG" -eq 1 ]; then
    capture_shell \
      "$out_dir/09-dmesg-alerts.txt" \
      "dmesg | grep storage and microvm patterns" \
      "dmesg 2>/dev/null | grep -Ei 'I/O|ext4|btrfs|blk|nvme|virtio|corrupt|error|journal|microvm' || true"
  else
    {
      printf '# collected_at=%s\n\n' "$(date -u +%FT%TZ)"
      echo 'dmesg capture skipped'
      printf '\n__exit_code=0\n'
    } >"$out_dir/09-dmesg-alerts.txt"
  fi

  capture_shell \
    "$out_dir/10-mounts.txt" \
    "findmnt /persist /var/lib/microvm /var/lib/microvms" \
    "findmnt /persist /var/lib/microvm /var/lib/microvms 2>/dev/null || true; echo; findmnt -R /persist 2>/dev/null || true"

  cat <<EOF >"$summary_file"
<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# FSS Root-Cause Host Checkpoint

- label: $LABEL
- collected_at: $(date -u +%FT%TZ)
- session_dir: $SESSION_DIR
- vm_name: $VM_NAME
- unit_name: $unit
- unit_log: $out_dir/05-unit-log.txt
- power_events: $out_dir/08-host-power-events.txt
- suspend_log: $out_dir/07-systemd-suspend.log.txt
- mounts: $out_dir/10-mounts.txt
EOF

  log "host checkpoint summary: $summary_file"
}

compare_checkpoints() {
  local from_dir=""
  local to_dir=""
  local out_dir=""
  local from_failed=""
  local to_failed=""
  local new_failed_count=0
  local resolved_failed_count=0
  local from_classification=""
  local to_classification=""
  local from_policy=""
  local to_policy=""
  local from_active=""
  local to_active=""

  require_root
  require_nonempty "$SESSION_DIR" "session-dir"
  require_nonempty "$FROM_LABEL" "from"
  require_nonempty "$TO_LABEL" "to"

  from_dir="$SESSION_DIR/guest/$FROM_LABEL/fss-debug"
  to_dir="$SESSION_DIR/guest/$TO_LABEL/fss-debug"
  out_dir="$SESSION_DIR/compare/$FROM_LABEL-vs-$TO_LABEL"
  from_failed="$out_dir/from-failed.txt"
  to_failed="$out_dir/to-failed.txt"

  if [ ! -d "$from_dir" ] || [ ! -d "$to_dir" ]; then
    printf 'error: comparison inputs are missing\nfrom=%s\nto=%s\n' "$from_dir" "$to_dir" >&2
    exit 3
  fi

  mkdir -p "$out_dir"

  compare_text "$from_dir/summary/summary.md" "$to_dir/summary/summary.md" "$out_dir/00-summary.diff.txt"
  compare_text "$from_dir/layout/01-journal-inventory.txt" "$to_dir/layout/01-journal-inventory.txt" "$out_dir/01-journal-inventory.diff.txt"
  compare_text "$from_dir/verify/02-failed-files.txt" "$to_dir/verify/02-failed-files.txt" "$out_dir/02-failed-files.diff.txt"
  compare_text "$from_dir/logs/06-power-events.txt" "$to_dir/logs/06-power-events.txt" "$out_dir/03-power-events.diff.txt"
  compare_text "$from_dir/services/11-user-services.txt" "$to_dir/services/11-user-services.txt" "$out_dir/04-user-services.diff.txt"
  compare_text "$from_dir/logs/07-user-services.log.txt" "$to_dir/logs/07-user-services.log.txt" "$out_dir/05-user-services-log.diff.txt"

  failed_paths "$from_dir/verify/02-failed-files.txt" >"$from_failed"
  failed_paths "$to_dir/verify/02-failed-files.txt" >"$to_failed"

  comm -13 "$from_failed" "$to_failed" >"$out_dir/new-failed-files.txt" || true
  comm -23 "$from_failed" "$to_failed" >"$out_dir/resolved-failed-files.txt" || true

  new_failed_count="$(sed '/^$/d' "$out_dir/new-failed-files.txt" | wc -l)"
  resolved_failed_count="$(sed '/^$/d' "$out_dir/resolved-failed-files.txt" | wc -l)"

  from_classification="$(extract_summary_field "$from_dir/summary/summary.md" "classification")"
  to_classification="$(extract_summary_field "$to_dir/summary/summary.md" "classification")"
  from_policy="$(extract_summary_field "$from_dir/summary/summary.md" "policy_outcome")"
  to_policy="$(extract_summary_field "$to_dir/summary/summary.md" "policy_outcome")"
  from_active="$(extract_summary_field "$from_dir/summary/summary.md" "active_system_failures")"
  to_active="$(extract_summary_field "$to_dir/summary/summary.md" "active_system_failures")"

  cat <<EOF >"$out_dir/summary.md"
<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# FSS Root-Cause Checkpoint Comparison

- session_dir: $SESSION_DIR
- from_label: $FROM_LABEL
- to_label: $TO_LABEL
- from_classification: ${from_classification:-unknown}
- to_classification: ${to_classification:-unknown}
- from_policy_outcome: ${from_policy:-unknown}
- to_policy_outcome: ${to_policy:-unknown}
- from_active_system_failures: ${from_active:-unknown}
- to_active_system_failures: ${to_active:-unknown}
- new_failed_files: $new_failed_count
- resolved_failed_files: $resolved_failed_count

## Key Files

- summary diff: $out_dir/00-summary.diff.txt
- journal inventory diff: $out_dir/01-journal-inventory.diff.txt
- failed file diff: $out_dir/02-failed-files.diff.txt
- power event diff: $out_dir/03-power-events.diff.txt
- new failed files: $out_dir/new-failed-files.txt
- resolved failed files: $out_dir/resolved-failed-files.txt
EOF

  log "comparison summary: $out_dir/summary.md"
}

while [ $# -gt 0 ]; do
  case "$1" in
  --session-dir)
    SESSION_DIR="$2"
    shift 2
    ;;
  --label)
    LABEL="$2"
    shift 2
    ;;
  --from)
    FROM_LABEL="$2"
    shift 2
    ;;
  --to)
    TO_LABEL="$2"
    shift 2
    ;;
  --vm-name)
    VM_NAME="$2"
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

case "$COMMAND" in
help | -h | --help)
  usage
  ;;
capture-guest)
  capture_guest
  ;;
capture-host)
  capture_host
  ;;
compare)
  compare_checkpoints
  ;;
*)
  printf 'error: unknown command %s\n' "$COMMAND" >&2
  usage >&2
  exit 2
  ;;
esac
