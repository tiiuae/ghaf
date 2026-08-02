#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# collect-logs.sh - snapshot the journals and unit state of every VM on a Ghaf device.
#
# One snapshot directory per run, so two runs can be diffed to separate a regression you
# introduced from noise that was always there. Unreachable VMs are recorded as such rather
# than failing the run: "gui-vm did not answer" is often the finding.

set -uo pipefail

HOST_IP=""
MACHINE=""
OUT=""
VMS=""
CONFIG="${GHAF_HW_TEST_CONFIG:-.github/skills/ghaf-hw-test/config.yaml}"
LOCAL_CONFIG="${GHAF_HW_TEST_LOCAL_CONFIG:-.github/skills/ghaf-hw-test/config.local.yaml}"
SSH_USER="${GHAF_SSH_USER:-ghaf}"
PREV_BOOT=0
PASSWORD="${GHAF_SSH_PASSWORD:-}"
# Fixed by modules/common/networking/hosts.nix, so it is safe to fall back to when the
# device cannot resolve or reach "ghaf-host" by name itself.
GHAF_HOST_IP=192.168.100.2

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Collect journals and unit state from a Ghaf device and all of its VMs.

Options:
  -m, --machine <NAME>  Read host_ip from config.yaml for this machine
  -i, --ip <ADDRESS>    Device address (overrides config)
  -o, --out <DIR>       Snapshot directory (default: ghaf-logs/<timestamp>)
      --vms "a b c"     Only these VMs (default: whatever the device reports)
      --prev-boot       Also collect the previous boot (journalctl -b -1)
      --password <PW>   Password for inner hops, when the device's own user has no key
                        to the other VMs (also GHAF_SSH_PASSWORD). Needs sshpass.
                        Without it those VMs are recorded UNREACHABLE.
  -h, --help            This message

Output layout:
  <DIR>/manifest.txt          what/when/where, plus deployed store paths
  <DIR>/ghaf-host/*.txt       host journal, failed units, dmesg, cmdline, microvm units
  <DIR>/<vm>/*.txt            per-VM journal, failed units, running system
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -m | --machine)
    MACHINE="$2"
    shift 2
    ;;
  -i | --ip)
    HOST_IP="$2"
    shift 2
    ;;
  -o | --out)
    OUT="$2"
    shift 2
    ;;
  --vms)
    VMS="$2"
    shift 2
    ;;
  --password)
    PASSWORD="$2"
    shift 2
    ;;
  --prev-boot)
    PREV_BOOT=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

# config.local.yaml is merged over config.yaml, which this script used not to do.
# host_ip is null in the shared file for every machine -- an address is a property
# of a desk, not of the project -- so reading only the shared file resolved it to
# null and reported "no device address" on a machine that was sitting right there.
# Semantics match get_device_config() in .github/skills/ghaf-hw-test/ghaf-hw-test,
# the canonical implementation: local wins per field, and a null in local does NOT
# blank a real value in the base, because the example file ships full of nulls and
# treating them as deletions would make a half-filled override destructive.
if [ -z "$HOST_IP" ] && [ -n "$MACHINE" ]; then
  HOST_IP=$(
    python3 - "$CONFIG" "$LOCAL_CONFIG" "$MACHINE" <<'PY'
import os
import sys

import yaml


def load(path):
    if not path or not os.path.exists(path):
        return {}
    with open(path) as fh:
        return yaml.safe_load(fh) or {}


shared, local, name = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
if name not in (shared.get("devices") or {}) and name not in (local.get("devices") or {}):
    sys.exit(f"No such machine in config: {name}")
dev = dict((shared.get("devices", {}) or {}).get(name) or {})
for key, value in ((local.get("devices", {}) or {}).get(name) or {}).items():
    if value is not None:
        dev[key] = value
print(dev.get("host_ip") or "")
PY
  ) || exit 1
fi

if [ -z "$HOST_IP" ]; then
  echo "No device address. Pass --ip, or --machine with host_ip set in" >&2
  echo "$LOCAL_CONFIG (see config.local.yaml.example for the shape)." >&2
  exit 1
fi

[ -z "$OUT" ] && OUT="ghaf-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# One multiplexed connection for the whole run: every VM command tunnels through it, so a
# 12-VM snapshot costs one authentication instead of ~40.
#
# The control path is a fresh per-run directory rather than the usual ~/.ssh/master-%r@%n:%p,
# and that is deliberate. Every Ghaf device numbers its VMs from the same 192.168.100.0/24,
# and the default path does not include the ProxyJump, so a master left open to one device's
# 192.168.100.2 will happily serve a later jump aimed at a different device -- silently
# snapshotting the wrong machine. A private path cannot collide with anyone else's.
CTRL="$(mktemp -d)/cm-%r@%h:%p"
#
# UserKnownHostsFile=/dev/null is load-bearing, not belt-and-braces. The shared subnet means
# a host key recorded for one device's gui-vm is a *changed* key on the next, and ssh answers
# a changed key by refusing and disabling password authentication -- so every VM records
# UNREACHABLE at once and the snapshot looks exactly like a device that never booted.
# StrictHostKeyChecking=no does not cover this: it auto-accepts keys that are new, not keys
# that conflict. Discarding the file is right here because a throwaway diagnostic connection
# to a lab device gains nothing from key continuity we cannot have anyway.
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CTRL" -o ControlPersist=60
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10 -o BatchMode=yes)

dev_ssh() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST_IP}" -- "$@"; }

# Two ways in, because the fleet is not uniformly reachable:
#
#   device  hop from the device itself (`ssh <vm>` on net-vm). One authentication for the
#           whole run and the fastest option -- but it only works where the device's own
#           user holds a key for that VM. On an Orin it does not: inter-VM ssh there wants
#           a password, which a BatchMode hop can never supply, and the symptom is every
#           VM recorded UNREACHABLE, indistinguishable from a device that failed to boot.
#   proxy   proxy-jump from here to the VM's address instead, so this machine's key (or
#           --password) does the authenticating rather than the device's.
#
# Which one works is decided per VM by probe_transports() before any collection starts.
declare -A VM_VIA
declare -A VM_IP

# Multiplexed like dev_ssh, and for a sharper reason than speed: collect_one issues about
# six commands per VM and the VMs run in parallel, so an unmultiplexed proxy opens ~30
# concurrent sessions through net-vm. Its sshd refuses them ("Connection timed out during
# banner exchange") and individual files land holding that error instead of log data --
# a partial snapshot that still looks successful. probe_transports connects once per VM
# first, so the masters exist before the parallel phase starts.
proxy_ssh() {
  local ip="$1"
  shift
  if [ -n "$PASSWORD" ]; then
    # PubkeyAuthentication=no as well as PreferredAuthentications=password: preference alone
    # still lets ssh offer keys, and a workstation with several loaded can exhaust the
    # server's auth attempts before the password is ever tried. The failure reads as a
    # rejected password rather than as too many keys.
    sshpass -p "$PASSWORD" ssh -o ControlMaster=auto -o "ControlPath=$CTRL" \
      -o ControlPersist=60 -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o "ProxyJump=${SSH_USER}@${HOST_IP}" "${SSH_USER}@${ip}" -- "$@"
  else
    ssh "${SSH_OPTS[@]}" -o "ProxyJump=${SSH_USER}@${HOST_IP}" "${SSH_USER}@${ip}" -- "$@"
  fi
}

hop_ssh() {
  local vm="$1"
  shift
  # Same reasoning as SSH_OPTS, one level in: the device's own known_hosts outlives a VM
  # reflash, and a VM that came back with a new host key would otherwise read as unreachable.
  dev_ssh ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$vm" "$@"
}

vm_ssh() {
  local vm="$1"
  shift
  case "${VM_VIA[$vm]:-hop}" in
  proxy) proxy_ssh "${VM_IP[$vm]}" "$@" ;;
  *) hop_ssh "$vm" "$@" ;;
  esac
}

# Serial, and deliberately before the parallel collection: the chosen transport has to be
# in the parent shell for the forked collectors to inherit it.
probe_transports() {
  local vm
  for vm in "$@"; do
    if hop_ssh "$vm" true 2>/dev/null; then
      VM_VIA[$vm]=hop
    elif [ -n "${VM_IP[$vm]:-}" ] && proxy_ssh "${VM_IP[$vm]}" true 2>/dev/null; then
      VM_VIA[$vm]=proxy
    else
      VM_VIA[$vm]=none
    fi
  done
}

if [ -n "$PASSWORD" ] && ! command -v sshpass >/dev/null 2>&1; then
  echo "--password given but sshpass is not on PATH; try: nix-shell -p sshpass" >&2
  exit 1
fi

echo "Connecting to ${SSH_USER}@${HOST_IP} ..." >&2
if ! dev_ssh true 2>/dev/null; then
  echo "Cannot reach ${SSH_USER}@${HOST_IP}." >&2
  echo "If the device is up but unreachable, use ghaf-connect's serial capture instead." >&2
  exit 1
fi

# Ask the device which VMs it has rather than assuming a fleet. A VM that should exist and
# doesn't appear here is itself a finding, so record both lists.
# Discovery has to survive the same problem collection does: if the hop to ghaf-host needs
# a password, asking the device for its own VM list fails and we would report an empty
# fleet. Settle ghaf-host's transport first, against its fixed address.
VM_IP["ghaf-host"]="$GHAF_HOST_IP"
probe_transports ghaf-host
if [ "${VM_VIA["ghaf-host"]}" = "none" ]; then
  echo "Cannot reach ghaf-host by hop or proxy-jump." >&2
  echo "If inter-VM ssh needs a password, pass --password (needs sshpass)." >&2
fi

HOSTS_RAW=$(vm_ssh ghaf-host cat /etc/hosts 2>/dev/null)
while read -r ip name _; do
  case "$ip" in 192.168.100.*) [ -n "$name" ] && VM_IP[$name]="$ip" ;; esac
done <<<"$HOSTS_RAW"

if [ -z "$VMS" ]; then
  UNITS=$(vm_ssh ghaf-host systemctl list-units --type=service --all --no-legend "microvm@*" 2>/dev/null |
    awk '{print $1}' | sed -n 's/^microvm@\(.*\)\.service$/\1/p' | sort -u)
  HOSTS=$(printf '%s\n' "$HOSTS_RAW" | awk '$1 ~ /^192\.168\.100\./ {print $2}' | sort -u)
  VMS=$(printf '%s\n%s\n' "$UNITS" "$HOSTS" | grep -v '^$' | grep -v '^ghaf-host$' | sort -u | tr '\n' ' ')
  printf 'microvm units:\n%s\n\n/etc/hosts entries:\n%s\n' "$UNITS" "$HOSTS" >"$OUT/vm-discovery.txt"
fi

# shellcheck disable=SC2086
probe_transports $VMS

echo "VMs: ghaf-host $VMS" >&2
for vm in ghaf-host $VMS; do
  [ "${VM_VIA[$vm]:-none}" = "none" ] || echo "  $vm via ${VM_VIA[$vm]}" >&2
done

collect_one() {
  local vm="$1"
  local dir="$OUT/$vm"
  mkdir -p "$dir"

  if [ "${VM_VIA[$vm]:-none}" = "none" ] || ! vm_ssh "$vm" true 2>/dev/null; then
    {
      echo "UNREACHABLE at $(date -Is)"
      echo "tried: hop from ${SSH_USER}@${HOST_IP}, proxy-jump to ${VM_IP[$vm]:-<no address>}"
      [ -n "$PASSWORD" ] || echo "no --password given; inter-VM ssh may require one"
    } >"$dir/UNREACHABLE.txt"
    echo "  $vm: unreachable" >&2
    return 0
  fi

  vm_ssh "$vm" journalctl -b --no-pager --no-hostname >"$dir/journal-boot.txt" 2>&1
  vm_ssh "$vm" systemctl --failed --no-legend --no-pager >"$dir/failed-units.txt" 2>&1
  vm_ssh "$vm" readlink /run/current-system >"$dir/current-system.txt" 2>&1
  vm_ssh "$vm" systemctl list-units --state=failed,activating --no-legend --no-pager \
    >"$dir/units-not-running.txt" 2>&1

  if [ "$PREV_BOOT" -eq 1 ]; then
    vm_ssh "$vm" journalctl -b -1 --no-pager --no-hostname >"$dir/journal-prevboot.txt" 2>&1
  fi

  if [ "$vm" = "ghaf-host" ]; then
    vm_ssh "$vm" dmesg >"$dir/dmesg.txt" 2>&1
    vm_ssh "$vm" cat /proc/cmdline >"$dir/cmdline.txt" 2>&1
    vm_ssh "$vm" systemctl list-units "microvm@*" --all --no-legend --no-pager \
      >"$dir/microvm-units.txt" 2>&1
    vm_ssh "$vm" cat /etc/hosts >"$dir/hosts.txt" 2>&1
  fi

  echo "  $vm: $(wc -l <"$dir/journal-boot.txt") journal lines" >&2
}

# Collect in parallel — the connection is already multiplexed, and a full fleet snapshot
# serially takes long enough that people skip taking one.
for vm in ghaf-host $VMS; do
  collect_one "$vm" &
done
wait

{
  echo "collected_at: $(date -Is)"
  echo "host_ip: $HOST_IP"
  echo "machine: ${MACHINE:-unspecified}"
  echo "vms: ghaf-host $VMS"
  echo "repo_rev: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "repo_dirty: $(if git diff --quiet 2>/dev/null; then echo no; else echo yes; fi)"
  echo ""
  echo "deployed systems:"
  for vm in ghaf-host $VMS; do
    if [ -f "$OUT/$vm/current-system.txt" ]; then
      echo "  $vm: $(cat "$OUT/$vm/current-system.txt")"
    else
      echo "  $vm: (unreachable)"
    fi
  done
} >"$OUT/manifest.txt"

echo "" >&2
echo "Snapshot written to $OUT" >&2
echo "Failed units across the fleet:" >&2
grep -l . "$OUT"/*/failed-units.txt 2>/dev/null | while read -r f; do
  vm=$(basename "$(dirname "$f")")
  while read -r line; do [ -n "$line" ] && echo "  $vm: $line" >&2; done <"$f"
done
