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

# Pull defaults from the shared device config so serial settings live in one place.
if [ -n "$MACHINE" ]; then
  if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG (run from the ghaf repo root, or set GHAF_HW_TEST_CONFIG)" >&2
    exit 1
  fi
  read -r cfg_dev cfg_baud <<<"$(
    python3 - "$CONFIG" "$MACHINE" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
dev = cfg.get("devices", {}).get(sys.argv[2])
if dev is None:
    sys.exit(f"No such machine in config: {sys.argv[2]}")
print(dev.get("serial_device") or "", dev.get("serial_baud") or "")
PY
  )"
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
