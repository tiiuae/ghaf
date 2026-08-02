#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# serial-run.sh - log in over the serial console and run commands non-interactively.
#
# serial-console.sh captures what a device says. This drives it: it logs in and
# runs a command list. That is what you need when the device is up but has no
# network - a net-vm that will not start, a NIC that was never passed through, a
# firewall rule that locked you out. In those cases every ssh-based tool in this
# repo is useless, and that is exactly when you most need to look inside.
#
# It matters most right after an install. A machine that flashed or netbooted
# successfully and then failed to bring up net-vm looks identical from outside to
# one that never booted at all, and only the console can tell the two apart.
#
# It is deliberately dumb: fixed sleeps, no prompt detection, no exit status from
# the target. A serial console gives you a byte stream, not a session, and
# pretending otherwise produces a tool that fails in ways nobody can debug. Treat
# the output as evidence to read, not as something to branch on. If a command
# needs longer than its slot, raise GHAF_SERIAL_STEP.
#
# Credentials default to the debug image's account (ghaf/ghaf - see
# modules/reference/personalize/accounts.nix and the config's test.default_password).
# A release image will not accept them.
#
# Usage:
#   serial-run.sh -m Orin-AGX 'systemctl --failed' 'ip -br addr'
#   serial-run.sh -d /dev/ttyACM0 -f commands.txt
#   echo 'journalctl -b -p err | tail -40' | serial-run.sh -m dell-7330 -

set -uo pipefail

DEVICE=""
BAUD=""
MACHINE=""
CMDFILE=""
USER_NAME="${GHAF_SERIAL_USER:-ghaf}"
PASSWORD="${GHAF_SERIAL_PASSWORD:-ghaf}"
STEP="${GHAF_SERIAL_STEP:-3}"
RAW_LOG=""

CONFIG="${GHAF_HW_TEST_CONFIG:-.github/skills/ghaf-hw-test/config.yaml}"
LOCAL_CONFIG="${GHAF_HW_TEST_LOCAL_CONFIG:-.github/skills/ghaf-hw-test/config.local.yaml}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <command> [command ...]
       $(basename "$0") [options] -f <file>
       $(basename "$0") [options] -          # read commands from stdin

Log in over the serial console and run commands, capturing the output.

Options:
  -m, --machine <NAME>  Read serial_device/serial_baud from config.yaml, with
                        config.local.yaml merged over it (darter-pro, Lenovo-X1,
                        dell-7330, NUC, Orin-AGX, Orin-NX)
  -d, --device <PATH>   Serial device node, e.g. /dev/ttyACM0
  -b, --baud <RATE>     Baud rate (default: from config, else 115200)
  -f, --file <FILE>     Read commands from FILE, one per line
  -s, --step <SECS>     Seconds to wait after each command (default: $STEP,
                        env GHAF_SERIAL_STEP). Raise it for slow commands.
      --raw-log <FILE>  Also keep the unfiltered capture, escape codes and all
  -h, --help            This message

Environment:
  GHAF_SERIAL_USER / GHAF_SERIAL_PASSWORD  default ghaf / ghaf (debug images)
  GHAF_HW_TEST_CONFIG / GHAF_HW_TEST_LOCAL_CONFIG  config paths

Exit: 0 if the session ran, 1 on setup failure, 2 usage error. The target's own
exit statuses are NOT propagated - add 'echo rc=\$?' to a command if you need one.
EOF
}

CMDS=()
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
  -f | --file)
    CMDFILE="$2"
    shift 2
    ;;
  -s | --step)
    STEP="$2"
    shift 2
    ;;
  --raw-log)
    RAW_LOG="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -)
    CMDFILE="/dev/stdin"
    shift
    ;;
  -*)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    CMDS+=("$1")
    shift
    ;;
  esac
done

if [ -n "$CMDFILE" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && CMDS+=("$line")
  done <"$CMDFILE"
fi

if [ ${#CMDS[@]} -eq 0 ]; then
  echo "error: no commands given" >&2
  usage >&2
  exit 2
fi

# Merge config.local.yaml over config.yaml, because serial_device is precisely a
# field the shared file cannot know: it is null there for every machine except
# the Orin-AGX. Reading only the shared file - which serial-console.sh and
# collect-logs.sh currently do - therefore resolves it to null on most devices
# and reports "no serial device configured" on a desk where one is plugged in.
# A null in the local file is a no-op, never a blank, so an unused key is
# harmless rather than destructive.
if [ -n "$MACHINE" ]; then
  if [ ! -f "$CONFIG" ]; then
    echo "error: config not found: $CONFIG" >&2
    echo "Run from the ghaf repo root, or set GHAF_HW_TEST_CONFIG." >&2
    exit 1
  fi
  read -r cfg_dev cfg_baud <<<"$(
    python3 - "$CONFIG" "$LOCAL_CONFIG" "$MACHINE" <<'PY'
import sys, yaml, os

def load(path):
    if not path or not os.path.exists(path):
        return {}
    with open(path) as fh:
        return yaml.safe_load(fh) or {}

shared, local, name = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
dev = dict(shared.get("devices", {}).get(name) or {})
if not dev and name not in (local.get("devices") or {}):
    sys.exit(f"No such machine in config: {name}")
for k, v in (local.get("devices", {}).get(name) or {}).items():
    if v is not None:
        dev[k] = v
print(dev.get("serial_device") or "", dev.get("serial_baud") or "")
PY
  )" || exit 1
  [ -z "$DEVICE" ] && DEVICE="$cfg_dev"
  [ -z "$BAUD" ] && BAUD="$cfg_baud"
fi
[ -z "$BAUD" ] && BAUD=115200

if [ -z "$DEVICE" ]; then
  echo "error: no serial device given and none configured." >&2
  echo "Candidates currently present:" >&2
  ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null >&2 || echo "  (none - is the cable attached?)" >&2
  echo "Set serial_device for this machine in $LOCAL_CONFIG." >&2
  exit 1
fi
if [ ! -c "$DEVICE" ]; then
  echo "error: not a character device: $DEVICE" >&2
  echo "Candidates currently present:" >&2
  ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null >&2 || echo "  (none - is the cable attached?)" >&2
  exit 1
fi

# A serial port is exclusive; silently competing with a stale picocom is a classic
# way to lose half the output.
if command -v fuser >/dev/null 2>&1 && fuser "$DEVICE" >/dev/null 2>&1; then
  echo "warning: another process already holds $DEVICE; output may be interleaved" >&2
fi

WORK="$(mktemp -d)"
CAP="${RAW_LOG:-$WORK/raw.log}"

if ! stty -F "$DEVICE" "$BAUD" raw -echo; then
  echo "error: could not configure $DEVICE at $BAUD" >&2
  rm -rf "$WORK"
  exit 1
fi

cat "$DEVICE" >"$CAP" 2>/dev/null &
CATPID=$!
trap 'kill "$CATPID" 2>/dev/null; wait "$CATPID" 2>/dev/null; rm -rf "$WORK"' EXIT

send() {
  printf '%s\r' "$1" >"$DEVICE"
  sleep "${2:-$STEP}"
}

echo "Driving $DEVICE at $BAUD baud as $USER_NAME" >&2

# Wake the console. If a shell is already open these lines echo harmlessly; if a
# login prompt is waiting, they log in. Doing both unconditionally is what keeps
# this working without prompt detection.
send "" 1
send "" 1
send "$USER_NAME" 2
send "$PASSWORD" 4

# Escape codes and a pager would make the capture unreadable.
send "export TERM=dumb SYSTEMD_COLORS=0 PAGER=cat" 2

for c in "${CMDS[@]}"; do
  send "echo ===GHAF-CMD=== $c" 1
  send "$c" "$STEP"
done
send "echo ===GHAF-END===" 2

sleep 1
kill "$CATPID" 2>/dev/null
wait "$CATPID" 2>/dev/null

# Strip CR, OSC title sequences and CSI colour codes. The target echoes our input
# back, so the ===GHAF-CMD=== markers are what make the transcript readable.
sed 's/\r$//' "$CAP" |
  sed -E 's/\x1b\][0-9]*;[^\x07]*\x07//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g' |
  sed -n '/===GHAF-CMD===/,/===GHAF-END===/p'

[ -n "$RAW_LOG" ] && echo "raw capture: $RAW_LOG" >&2
exit 0
