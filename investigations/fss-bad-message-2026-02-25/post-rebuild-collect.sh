#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# shellcheck disable=SC2016

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"

# Reuse the same verify bucketing logic as the service and fss-test.
# shellcheck disable=SC1091
source "${REPO_ROOT}/modules/common/logging/fss-verify-classifier.sh"

HOST_TARGET="${HOST_TARGET:-root@ghaf-host}"
NET_VM_TARGET="${NET_VM_TARGET:-ghaf@net-vm}"
NET_VM_PROXYJUMP="${NET_VM_PROXYJUMP:-${HOST_TARGET}}"
NET_VM_PASSWORD="${NET_VM_PASSWORD:-ghaf}"
ENABLE_NET_VM=1
SOAK_MINUTES=60
INTERVAL_SECONDS=300
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/raw-logs/post-rebuild-$(date -u +%Y%m%dT%H%M%SZ)}"

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

usage() {
  cat <<'EOF'
Usage: post-rebuild-collect.sh [options]

Collect the post-rebuild FSS validation packet:
- host baseline
- optional net-vm baseline
- 1 hour host soak by default
- classification summary and manual VM follow-up instructions

Options:
  --host-target <ssh-target>         Default: root@ghaf-host
  --net-vm-target <ssh-target>       Default: ghaf@net-vm
  --net-vm-proxyjump <ssh-target>    Default: root@ghaf-host
  --net-vm-password <password>       Default: ghaf
  --skip-net-vm                      Skip net-vm baseline collection
  --soak-minutes <minutes>           Default: 60
  --interval-seconds <seconds>       Default: 300
  --skip-soak                        Disable the soak loop
  --out-dir <path>                   Output directory
  --help                             Show this help

Environment overrides:
  HOST_TARGET, NET_VM_TARGET, NET_VM_PROXYJUMP, NET_VM_PASSWORD, OUT_DIR
EOF
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
  --host-target)
    HOST_TARGET="$2"
    shift 2
    ;;
  --net-vm-target)
    NET_VM_TARGET="$2"
    shift 2
    ;;
  --net-vm-proxyjump)
    NET_VM_PROXYJUMP="$2"
    shift 2
    ;;
  --net-vm-password)
    NET_VM_PASSWORD="$2"
    shift 2
    ;;
  --skip-net-vm)
    ENABLE_NET_VM=0
    shift
    ;;
  --soak-minutes)
    SOAK_MINUTES="$2"
    shift 2
    ;;
  --interval-seconds)
    INTERVAL_SECONDS="$2"
    shift 2
    ;;
  --skip-soak)
    SOAK_MINUTES=0
    shift
    ;;
  --out-dir)
    OUT_DIR="$2"
    shift 2
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

require_numeric "$SOAK_MINUTES" "soak-minutes"
require_numeric "$INTERVAL_SECONDS" "interval-seconds"

mkdir -p \
  "${OUT_DIR}/host" \
  "${OUT_DIR}/net-vm" \
  "${OUT_DIR}/soak" \
  "${OUT_DIR}/summary"

HOST_SUMMARY_STATUS="unknown"
HOST_SUMMARY_TAGS=""
HOST_SERVICE_RESULT="unknown"
HOST_SERVICE_EXIT="unknown"
HOST_FSS_TEST_EXIT="unknown"
HOST_RECOVERY_LINES=0

NET_VM_SUMMARY_STATUS="skipped"
NET_VM_SUMMARY_TAGS=""
NET_VM_SERVICE_RESULT="unknown"
NET_VM_SERVICE_EXIT="unknown"
NET_VM_FSS_TEST_EXIT="unknown"
NET_VM_RECOVERY_LINES=0

MANUAL_FOLLOWUP_REASON=""

extract_exit_code() {
  local file="$1"

  awk -F= '/^__exit_code=/{code=$2} END{print code}' "$file"
}

payload_lines() {
  local file="$1"

  sed '/^#/d;/^$/d;/^__exit_code=/d' "$file"
}

capture_command() {
  local mode="$1"
  local file="$2"
  local command="$3"
  local exit_code=0
  local remote_command=""

  {
    printf '# collected_at=%s\n' "$(date -u +%FT%TZ)"
    printf '# mode=%s\n' "$mode"
    printf '# command=%s\n\n' "$command"

    if [[ $mode == "host" ]]; then
      if ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST_TARGET" "$command"; then
        exit_code=0
      else
        exit_code=$?
      fi
    else
      if command -v sshpass >/dev/null 2>&1; then
        remote_command="$command"
        if [[ $NET_VM_TARGET != "root" && $NET_VM_TARGET != root@* ]]; then
          printf -v remote_command "printf '%%s\\n' %q | sudo -S -p '' bash -lc %q" "$NET_VM_PASSWORD" "$command"
        fi
        if sshpass -p "$NET_VM_PASSWORD" ssh \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o PubkeyAuthentication=no \
          -o PreferredAuthentications=password,keyboard-interactive \
          -o ConnectTimeout=12 \
          -J "$NET_VM_PROXYJUMP" \
          "$NET_VM_TARGET" \
          "$remote_command"; then
          exit_code=0
        else
          exit_code=$?
        fi
      else
        printf 'ERROR: sshpass is not installed; cannot reach %s\n' "$NET_VM_TARGET"
        exit_code=127
      fi
    fi

    printf '\n__exit_code=%s\n' "$exit_code"
  } >"$file" 2>&1
}

classify_verify_capture() {
  local file="$1"
  local status="clean"
  local tags=""
  local output

  output="$(payload_lines "$file")"
  tags="$(fss_reason_tags_from_output "$output")"
  fss_classify_verify_output "$output"
  tags="$(fss_classification_tags "$tags")"

  if grep -qi 'ERROR: sshpass is not installed' "$file"; then
    status="access_blocked"
  elif grep -qi 'ERROR: Required key not available' "$file"; then
    status="key_defect"
  elif [[ ${FSS_KEY_PARSE_ERROR} -eq 1 ]] || [[ ${FSS_KEY_REQUIRED_ERROR} -eq 1 ]]; then
    status="key_defect"
  elif [[ -n ${FSS_ACTIVE_SYSTEM_FAILURES} ]] || [[ -n ${FSS_OTHER_FAILURES} ]]; then
    status="active_failure"
  elif [[ -n ${FSS_ARCHIVED_SYSTEM_FAILURES} ]] || [[ -n ${FSS_USER_FAILURES} ]]; then
    status="warning_only"
  elif [[ -n ${FSS_TEMP_FAILURES} ]]; then
    status="temp_only"
  elif [[ "$(extract_exit_code "$file")" != "0" ]]; then
    status="verify_nonzero_no_fail"
  fi

  printf '%s|%s\n' "$status" "$tags"
}

extract_systemctl_field() {
  local file="$1"
  local field="$2"

  awk -F= -v field="$field" '$1 == field { value=$2 } END{ print value }' "$file"
}

count_recovery_lines() {
  local file="$1"

  payload_lines "$file" | grep -Eic 'corrupt|unclean|renam|I/O|Bad message|journal' || true
}

trigger_manual_followup() {
  local component="$1"
  local status="$2"
  local service_result="$3"
  local service_exit="$4"
  local fss_test_exit="$5"

  if [[ $status == "clean" || $status == "temp_only" ]]; then
    if [[ $service_result != "success" && $service_result != "" && $service_result != "unknown" ]]; then
      MANUAL_FOLLOWUP_REASON="${component} service result ${service_result}"
    elif [[ $service_exit != "0" && $service_exit != "" && $service_exit != "unknown" ]]; then
      MANUAL_FOLLOWUP_REASON="${component} service exit ${service_exit}"
    elif [[ $fss_test_exit != "0" && $fss_test_exit != "" && $fss_test_exit != "unknown" ]]; then
      MANUAL_FOLLOWUP_REASON="${component} fss-test exit ${fss_test_exit}"
    else
      return 0
    fi
  else
    MANUAL_FOLLOWUP_REASON="${component} classification ${status}"
  fi
}

write_manual_followup() {
  local file="${OUT_DIR}/summary/manual-vm-followup.md"

  cat >"$file" <<EOF
<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# Manual VM Follow-Up

Manual \`admin-vm\` and \`business-vm\` collection is required because: ${MANUAL_FOLLOWUP_REASON}

Run the packet below inside each VM and save the full output with a UTC timestamp.

\`\`\`bash
date -u
hostname
id -un
systemctl status --no-pager journal-fss-setup.service || true
systemctl show journal-fss-verify.service -p ActiveState,SubState,Result,ExecMainStatus,ExecMainCode --no-pager || true
journalctl -u journal-fss-verify.service --no-pager -b -n 300 || true
journalctl -u systemd-journald --no-pager -b -n 400 | grep -Ei "corrupt|unclean|renam|I/O|Bad message|journal" || true
journalctl --list-boots --no-pager || true

MID=\$(cat /etc/machine-id)
FSS_CONFIG="/var/log/journal/\$MID/fss-config"
KEY_DIR=""
if [ -s "\$FSS_CONFIG" ]; then
  KEY_DIR=\$(cat "\$FSS_CONFIG")
else
  HOSTNAME=\$(hostname)
  for CANDIDATE in "/persist/common/journal-fss/\$HOSTNAME" "/etc/common/journal-fss/\$HOSTNAME"; do
    if [ -d "\$CANDIDATE" ]; then
      KEY_DIR="\$CANDIDATE"
      break
    fi
  done
fi

echo "machine_id=\$MID"
echo "key_dir=\$KEY_DIR"
ls -l /var/log/journal/\$MID/fss* /run/log/journal/\$MID/fss* 2>/dev/null || true
if [ -n "\$KEY_DIR" ]; then
  ls -l "\$KEY_DIR" 2>/dev/null || true
fi

if [ -n "\$KEY_DIR" ] && [ -r "\$KEY_DIR/verification-key" ] && [ -s "\$KEY_DIR/verification-key" ]; then
  KEY=\$(cat "\$KEY_DIR/verification-key")
  journalctl --verify --verify-key="\$KEY" || true

  if [ -f "/var/log/journal/\$MID/system.journal" ]; then
    journalctl --verify --verify-key="\$KEY" --file="/var/log/journal/\$MID/system.journal" || true
  elif [ -f "/run/log/journal/\$MID/system.journal" ]; then
    journalctl --verify --verify-key="\$KEY" --file="/run/log/journal/\$MID/system.journal" || true
  fi
else
  echo "ERROR: Required key not available"
fi

if command -v fss-test >/dev/null 2>&1; then
  fss-test || true
fi
\`\`\`

Classify the results with the same buckets as the host:
- \`ACTIVE_SYSTEM\`
- \`ARCHIVED_SYSTEM\`
- \`USER_JOURNAL\`
- \`TEMP\`
- \`KEY_DEFECT\`
EOF
}

collect_host() {
  log "collecting host baseline"
  capture_command host "${OUT_DIR}/host/00-identity.txt" \
    'date -u; hostname; uptime; cat /etc/os-release; nixos-version || true; readlink -f /run/current-system || true; systemctl --failed --no-pager || true; journalctl --list-boots --no-pager'
  capture_command host "${OUT_DIR}/host/01-fss-setup-status.txt" \
    'systemctl status --no-pager journal-fss-setup.service'
  capture_command host "${OUT_DIR}/host/02-key-state.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; echo "machine_id=$MID"; echo "key_dir=$KEY_DIR"; ls -l /var/log/journal/$MID/fss* /run/log/journal/$MID/fss* 2>/dev/null || true; if [ -n "$KEY_DIR" ]; then ls -l "$KEY_DIR" 2>/dev/null || true; fi'
  capture_command host "${OUT_DIR}/host/03-verify-service-show.txt" \
    'systemctl show journal-fss-verify.service -p ActiveState,SubState,Result,ExecMainStatus,ExecMainCode --no-pager'
  capture_command host "${OUT_DIR}/host/04-verify-service-status.txt" \
    'systemctl status --no-pager journal-fss-verify.service'
  capture_command host "${OUT_DIR}/host/05-verify-service-log.txt" \
    'journalctl -u journal-fss-verify.service --no-pager -b -n 300'
  capture_command host "${OUT_DIR}/host/06-journald-log.txt" \
    'journalctl -u systemd-journald --no-pager -b -n 400 | grep -Ei "corrupt|unclean|renam|I/O|Bad message|journal" || true'
  capture_command host "${OUT_DIR}/host/07-verify-full.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; if [ -z "$KEY_DIR" ] || [ ! -r "$KEY_DIR/verification-key" ] || [ ! -s "$KEY_DIR/verification-key" ]; then echo "ERROR: Required key not available"; exit 2; fi; KEY=$(cat "$KEY_DIR/verification-key"); journalctl --verify --verify-key="$KEY"'
  capture_command host "${OUT_DIR}/host/08-verify-system-journal.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; if [ -z "$KEY_DIR" ] || [ ! -r "$KEY_DIR/verification-key" ] || [ ! -s "$KEY_DIR/verification-key" ]; then echo "ERROR: Required key not available"; exit 2; fi; KEY=$(cat "$KEY_DIR/verification-key"); if [ -f "/var/log/journal/$MID/system.journal" ]; then journalctl --verify --verify-key="$KEY" --file="/var/log/journal/$MID/system.journal"; elif [ -f "/run/log/journal/$MID/system.journal" ]; then journalctl --verify --verify-key="$KEY" --file="/run/log/journal/$MID/system.journal"; else echo "ERROR: system.journal not found"; exit 3; fi'
  capture_command host "${OUT_DIR}/host/09-fss-test.txt" \
    'fss-test'
}

collect_net_vm() {
  if [[ $ENABLE_NET_VM -eq 0 ]]; then
    log "skipping net-vm baseline"
    return 0
  fi

  log "collecting net-vm baseline"
  capture_command net-vm "${OUT_DIR}/net-vm/00-identity.txt" \
    'date -u; hostname; uptime; cat /etc/os-release; nixos-version || true; readlink -f /run/current-system || true; systemctl --failed --no-pager || true; journalctl --list-boots --no-pager'
  capture_command net-vm "${OUT_DIR}/net-vm/01-fss-setup-status.txt" \
    'systemctl status --no-pager journal-fss-setup.service'
  capture_command net-vm "${OUT_DIR}/net-vm/02-key-state.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; echo "machine_id=$MID"; echo "key_dir=$KEY_DIR"; ls -l /var/log/journal/$MID/fss* /run/log/journal/$MID/fss* 2>/dev/null || true; if [ -n "$KEY_DIR" ]; then ls -l "$KEY_DIR" 2>/dev/null || true; fi'
  capture_command net-vm "${OUT_DIR}/net-vm/03-verify-service-show.txt" \
    'systemctl show journal-fss-verify.service -p ActiveState,SubState,Result,ExecMainStatus,ExecMainCode --no-pager'
  capture_command net-vm "${OUT_DIR}/net-vm/04-verify-service-status.txt" \
    'systemctl status --no-pager journal-fss-verify.service'
  capture_command net-vm "${OUT_DIR}/net-vm/05-verify-service-log.txt" \
    'journalctl -u journal-fss-verify.service --no-pager -b -n 300'
  capture_command net-vm "${OUT_DIR}/net-vm/06-journald-log.txt" \
    'journalctl -u systemd-journald --no-pager -b -n 400 | grep -Ei "corrupt|unclean|renam|I/O|Bad message|journal" || true'
  capture_command net-vm "${OUT_DIR}/net-vm/07-verify-full.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; if [ -z "$KEY_DIR" ] || [ ! -r "$KEY_DIR/verification-key" ] || [ ! -s "$KEY_DIR/verification-key" ]; then echo "ERROR: Required key not available"; exit 2; fi; KEY=$(cat "$KEY_DIR/verification-key"); journalctl --verify --verify-key="$KEY"'
  capture_command net-vm "${OUT_DIR}/net-vm/08-verify-system-journal.txt" \
    'MID=$(cat /etc/machine-id); FSS_CONFIG="/var/log/journal/$MID/fss-config"; KEY_DIR=""; if [ -s "$FSS_CONFIG" ]; then KEY_DIR=$(cat "$FSS_CONFIG"); else HOSTNAME=$(hostname); for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do if [ -d "$CANDIDATE" ]; then KEY_DIR="$CANDIDATE"; break; fi; done; fi; if [ -z "$KEY_DIR" ] || [ ! -r "$KEY_DIR/verification-key" ] || [ ! -s "$KEY_DIR/verification-key" ]; then echo "ERROR: Required key not available"; exit 2; fi; KEY=$(cat "$KEY_DIR/verification-key"); if [ -f "/var/log/journal/$MID/system.journal" ]; then journalctl --verify --verify-key="$KEY" --file="/var/log/journal/$MID/system.journal"; elif [ -f "/run/log/journal/$MID/system.journal" ]; then journalctl --verify --verify-key="$KEY" --file="/run/log/journal/$MID/system.journal"; else echo "ERROR: system.journal not found"; exit 3; fi'
  capture_command net-vm "${OUT_DIR}/net-vm/09-fss-test.txt" \
    'fss-test'
}

collect_host_probe() {
  local file="${OUT_DIR}/summary/host-probe.txt"
  local ok=0
  local i

  : >"$file"
  for i in {1..5}; do
    {
      printf 'attempt=%s\n' "$i"
      date -u +%FT%TZ
      if ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST_TARGET" 'hostname; date -u +%FT%TZ'; then
        printf 'result=ok\n\n'
        ok=$((ok + 1))
      else
        printf 'result=fail\n\n'
      fi
    } >>"$file" 2>&1
  done

  if [[ $ok -lt 5 ]]; then
    log "host probe failed (${ok}/5 successful)"
    return 1
  fi

  log "host probe passed (5/5 successful)"
  return 0
}

collect_soak() {
  local samples
  local i
  local file
  local lookback_seconds

  if [[ $SOAK_MINUTES -eq 0 ]]; then
    log "soak disabled"
    return 0
  fi

  if [[ $INTERVAL_SECONDS -eq 0 ]]; then
    printf 'error: interval-seconds must be greater than zero when soak is enabled\n' >&2
    exit 2
  fi

  samples=$(((SOAK_MINUTES * 60) / INTERVAL_SECONDS))
  if [[ $samples -lt 1 ]]; then
    printf 'error: soak-minutes %s with interval-seconds %s produces zero samples\n' "$SOAK_MINUTES" "$INTERVAL_SECONDS" >&2
    exit 2
  fi

  lookback_seconds=$((INTERVAL_SECONDS + 60))
  log "starting host soak (${samples} samples, ${INTERVAL_SECONDS}s interval)"
  for ((i = 1; i <= samples; i++)); do
    file="${OUT_DIR}/soak/host-sample-$(printf '%02d' "$i").txt"
    capture_command host "$file" \
      "date -u; systemctl show journal-fss-verify.service -p Result,ExecMainStatus --no-pager; journalctl -u journal-fss-verify.service --since '${lookback_seconds} seconds ago' --no-pager; journalctl -u systemd-journald --since '${lookback_seconds} seconds ago' --no-pager | grep -Ei \"corrupt|unclean|renam|I/O|Bad message|journal\" || true"
    if [[ $i -lt $samples ]]; then
      sleep "$INTERVAL_SECONDS"
    fi
  done
}

write_summary() {
  local host_class
  local net_vm_class
  local summary_file="${OUT_DIR}/summary/baseline-summary.md"
  local sample
  local soak_alerts=0

  IFS='|' read -r HOST_SUMMARY_STATUS HOST_SUMMARY_TAGS < <(classify_verify_capture "${OUT_DIR}/host/07-verify-full.txt")
  HOST_SERVICE_RESULT="$(extract_systemctl_field "${OUT_DIR}/host/03-verify-service-show.txt" "Result")"
  HOST_SERVICE_EXIT="$(extract_systemctl_field "${OUT_DIR}/host/03-verify-service-show.txt" "ExecMainStatus")"
  HOST_FSS_TEST_EXIT="$(extract_exit_code "${OUT_DIR}/host/09-fss-test.txt")"
  HOST_RECOVERY_LINES="$(count_recovery_lines "${OUT_DIR}/host/06-journald-log.txt")"
  trigger_manual_followup "host" "$HOST_SUMMARY_STATUS" "$HOST_SERVICE_RESULT" "$HOST_SERVICE_EXIT" "$HOST_FSS_TEST_EXIT"
  host_class="| host | ${HOST_SUMMARY_STATUS} | ${HOST_SUMMARY_TAGS:-none} | ${HOST_SERVICE_RESULT:-unknown} | ${HOST_SERVICE_EXIT:-unknown} | ${HOST_FSS_TEST_EXIT:-unknown} | ${HOST_RECOVERY_LINES} |"

  if [[ $ENABLE_NET_VM -eq 1 ]]; then
    IFS='|' read -r NET_VM_SUMMARY_STATUS NET_VM_SUMMARY_TAGS < <(classify_verify_capture "${OUT_DIR}/net-vm/07-verify-full.txt")
    NET_VM_SERVICE_RESULT="$(extract_systemctl_field "${OUT_DIR}/net-vm/03-verify-service-show.txt" "Result")"
    NET_VM_SERVICE_EXIT="$(extract_systemctl_field "${OUT_DIR}/net-vm/03-verify-service-show.txt" "ExecMainStatus")"
    NET_VM_FSS_TEST_EXIT="$(extract_exit_code "${OUT_DIR}/net-vm/09-fss-test.txt")"
    NET_VM_RECOVERY_LINES="$(count_recovery_lines "${OUT_DIR}/net-vm/06-journald-log.txt")"
    if [[ -z $MANUAL_FOLLOWUP_REASON ]]; then
      trigger_manual_followup "net-vm" "$NET_VM_SUMMARY_STATUS" "$NET_VM_SERVICE_RESULT" "$NET_VM_SERVICE_EXIT" "$NET_VM_FSS_TEST_EXIT"
    fi
    net_vm_class="| net-vm | ${NET_VM_SUMMARY_STATUS} | ${NET_VM_SUMMARY_TAGS:-none} | ${NET_VM_SERVICE_RESULT:-unknown} | ${NET_VM_SERVICE_EXIT:-unknown} | ${NET_VM_FSS_TEST_EXIT:-unknown} | ${NET_VM_RECOVERY_LINES} |"
  else
    net_vm_class="| net-vm | skipped | none | skipped | skipped | skipped | skipped |"
  fi

  if compgen -G "${OUT_DIR}/soak/host-sample-*.txt" >/dev/null; then
    for sample in "${OUT_DIR}"/soak/host-sample-*.txt; do
      if payload_lines "$sample" | grep -Eq 'Result=failed|ExecMainStatus=[1-9][0-9]*|corrupt|unclean|renam|I/O|Bad message'; then
        soak_alerts=$((soak_alerts + 1))
      fi
    done
  fi

  {
    cat <<EOF
<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# Post-Rebuild Baseline Summary

- collected_at: $(date -u +%FT%TZ)
- host_target: ${HOST_TARGET}
- net_vm_target: $(if [[ $ENABLE_NET_VM -eq 1 ]]; then printf '%s via %s' "$NET_VM_TARGET" "$NET_VM_PROXYJUMP"; else printf 'skipped'; fi)
- soak_minutes: ${SOAK_MINUTES}
- interval_seconds: ${INTERVAL_SECONDS}

| Component | Verify classification | Tags | Service result | Service exit | fss-test exit | Journald recovery lines |
|---|---|---|---|---|---|---|
${host_class}
${net_vm_class}

- host_soak_alert_samples: ${soak_alerts}
- manual_vm_followup: $(if [[ -n $MANUAL_FOLLOWUP_REASON ]]; then printf 'required'; else printf 'not required'; fi)
EOF

    if [[ -n $MANUAL_FOLLOWUP_REASON ]]; then
      printf -- "- manual_vm_followup_reason: %s\n" "$MANUAL_FOLLOWUP_REASON"
      printf -- "- manual_vm_followup_file: %s\n" "${OUT_DIR}/summary/manual-vm-followup.md"
    fi
  } >"$summary_file"

  if [[ -n $MANUAL_FOLLOWUP_REASON ]]; then
    write_manual_followup
  fi

  log "wrote summary to ${summary_file}"
}

main() {
  log "output dir: ${OUT_DIR}"

  if ! collect_host_probe; then
    log "aborting due to unstable host access"
    exit 1
  fi

  collect_host
  collect_net_vm
  collect_soak
  write_summary

  log "post-rebuild collection complete"
}

main "$@"
