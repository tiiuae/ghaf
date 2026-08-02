#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# serial-console.sh - attach to a Ghaf device's serial console, or capture from it
# non-interactively.
#
# Capture mode exists because the interesting case is a device that never reaches the
# network: a kernel panic, a failed initrd, a bootloader that hangs. Serial is the only
# evidence there, and an agent cannot drive an interactive terminal.

set -euo pipefail

DEVICE=""
BAUD=""
LOG=""
CAPTURE=""
CONFIG="${GHAF_HW_TEST_CONFIG:-.github/skills/ghaf-hw-test/config.yaml}"
LOCAL_CONFIG="${GHAF_HW_TEST_LOCAL_CONFIG:-.github/skills/ghaf-hw-test/config.local.yaml}"
MACHINE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Attach to a serial console, or capture from it for a fixed time.

Options:
  -m, --machine <NAME>   Read serial_device/serial_baud from config.yaml for this
                         machine (darter-pro, Orin-AGX, ...). Explicit flags win.
  -d, --device <PATH>    Serial device node, e.g. /dev/ttyUSB0
  -b, --baud <RATE>      Baud rate (default: 115200)
  -c, --capture <SECS>   Capture for SECS seconds and exit, instead of attaching.
                         Use this when you need evidence, not a session.
  -l, --log <FILE>       Write output here (default: a timestamped file in \$PWD)
  -h, --help             This message

Examples:
  $(basename "$0") -m Orin-AGX -c 120       # capture two minutes of boot output
  $(basename "$0") -d /dev/ttyUSB0          # interactive session, logged
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -m | --machine)
    MACHINE="$2"
    shift 2
    ;;
  -d | --device)
    DEVICE="$2"
    shift 2
    ;;
  -b | --baud)
    BAUD="$2"
    shift 2
    ;;
  -c | --capture)
    CAPTURE="$2"
    shift 2
    ;;
  -l | --log)
    LOG="$2"
    shift 2
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

# Pull defaults from the device config so serial settings live in one place.
#
# config.local.yaml is merged over config.yaml, which this script used not to do.
# That mattered: serial_device is null in the shared file for every machine
# except the Orin-AGX, because which port a cable lands on is a property of a
# desk, not of the project. Reading only the shared file therefore resolved it to
# null on most devices and reported "no serial device configured" on a desk where
# one was plugged in. Semantics match get_device_config() in
# .github/skills/ghaf-hw-test/ghaf-hw-test, which is the canonical implementation:
# local wins per field, and a null in local does NOT blank a real value in the
# base -- the example file ships full of nulls, so treating them as deletions
# would make a half-filled override destructive.
if [ -n "$MACHINE" ]; then
  if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG (run from the ghaf repo root, or set GHAF_HW_TEST_CONFIG)" >&2
    exit 1
  fi
  read -r cfg_dev cfg_baud <<<"$(
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
print(dev.get("serial_device") or "", dev.get("serial_baud") or "")
PY
  )" || exit 1
  [ -z "$DEVICE" ] && DEVICE="$cfg_dev"
  [ -z "$BAUD" ] && BAUD="$cfg_baud"
fi

[ -z "$BAUD" ] && BAUD=115200

if [ -z "$DEVICE" ]; then
  echo "No serial device given and none configured." >&2
  echo "Candidates currently present:" >&2
  ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null >&2 || echo "  (none — is the cable attached?)" >&2
  exit 1
fi

if [ ! -c "$DEVICE" ]; then
  echo "Not a character device: $DEVICE" >&2
  echo "Candidates currently present:" >&2
  ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null >&2 || echo "  (none — is the cable attached?)" >&2
  exit 1
fi

# A serial port is exclusive. Silently competing with a stale picocom is a classic way to
# lose half the boot log, so say so plainly instead.
if command -v fuser >/dev/null 2>&1 && fuser "$DEVICE" >/dev/null 2>&1; then
  echo "Warning: another process already holds $DEVICE:" >&2
  fuser -v "$DEVICE" >&2 || true
  echo "Output may be interleaved or lost. Close it first if you can." >&2
fi

if [ -z "$LOG" ]; then
  LOG="serial-$(basename "$DEVICE")-$(date +%Y%m%d-%H%M%S).log"
fi

if [ -n "$CAPTURE" ]; then
  echo "Capturing ${CAPTURE}s from $DEVICE at ${BAUD} baud -> $LOG" >&2
  stty -F "$DEVICE" "$BAUD" raw -echo
  # Exit status 124 from timeout just means the window elapsed, which is the normal
  # outcome here — only a genuine read error should fail the script.
  set +e
  timeout "$CAPTURE" cat "$DEVICE" | tee "$LOG"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
    echo "Read from $DEVICE failed (exit $rc)" >&2
    exit "$rc"
  fi
  echo "Captured $(wc -l <"$LOG") lines to $LOG" >&2
  exit 0
fi

echo "Attaching to $DEVICE at ${BAUD} baud, logging to $LOG" >&2
if command -v picocom >/dev/null 2>&1; then
  echo "Exit with Ctrl-A Ctrl-X" >&2
  exec picocom --baud "$BAUD" --logfile "$LOG" "$DEVICE"
elif command -v tio >/dev/null 2>&1; then
  echo "Exit with Ctrl-T q" >&2
  exec tio --baudrate "$BAUD" --log --log-file "$LOG" "$DEVICE"
else
  echo "Neither picocom nor tio found. Either:" >&2
  echo "  nix-shell -p picocom --run '$(basename "$0") -d $DEVICE -b $BAUD'" >&2
  echo "  or use --capture <secs>, which needs only coreutils." >&2
  exit 1
fi
