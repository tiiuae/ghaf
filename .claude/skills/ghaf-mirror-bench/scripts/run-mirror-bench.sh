#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# run-mirror-bench.sh - drive ids-mirror-bench on a Ghaf device from here.
#
# The benchmark itself lives on net-vm and needs three things this script
# supplies: an iperf3 server it can reach (started locally, torn down after),
# root on net-vm (sudo there wants a password), and somewhere to keep the
# output. It also restores mirroring if the run is interrupted -- the bench
# toggles ids-mirror ON/OFF per pair, so a Ctrl-C during an OFF window would
# otherwise leave the device with mirroring silently disabled.

set -euo pipefail

CONFIG="${GHAF_HW_TEST_CONFIG:-.github/skills/ghaf-hw-test/config.yaml}"
LOCAL_CONFIG="${GHAF_HW_TEST_LOCAL_CONFIG:-.github/skills/ghaf-hw-test/config.local.yaml}"

MACHINE=""
HOST_IP=""
IFACE=""
MODE="ab"
WINDOW=""
ITERATIONS=""
BANDWIDTH=""
SWEEP_MIN=""
SWEEP_MAX=""
SWEEP_STEP=""
OUT=""
PASSWORD="ghaf"
IPERF_SERVER=""
NO_IPERF=0
NO_HOST_BENCH=0
DRY_RUN=0
EXTRA=()

usage() {
  cat <<'EOF'
Usage: run-mirror-bench.sh [OPTIONS] [-- EXTRA_BENCH_ARGS...]

  -m, --machine <NAME>   Read host_ip from config.yaml/config.local.yaml
  -i, --ip <ADDRESS>     net-vm address (overrides config)
      --iface <IFACE>    Physical NIC to measure. Optional: with one NIC it is
                         picked automatically, with several you are asked.
                         Names are not stable across targets or re-plugs, so
                         prefer being asked over pasting a remembered name.
      --mode <ab|sweep>  ab: interleaved Mirror ON/OFF pairs (default)
                         sweep: bandwidth sweep with plots (needs iperf3)
      --window <SEC>     Seconds per ON/OFF slot (bench default: 30)
      --iterations <N>   ON/OFF pairs, or pairs per sweep step (default: 10)
      --bandwidth <BW>   iperf3 target bandwidth for ab mode (e.g. 100M)
      --sweep-min <BW>   Sweep lower bound (default: same as step)
      --sweep-max <BW>   Sweep upper bound (required for --mode sweep)
      --sweep-step <BW>  Sweep step (bench default: 5M)
      --iperf-server <H> Use this iperf3 server instead of starting one here
      --no-iperf         Skip iperf3 entirely (ping/CPU/RAM only; not for sweep)
      --no-host-bench    Skip host CPU measurement via ids-bench-server
  -o, --out <DIR>        Output directory (default: ghaf-bench/<timestamp>)
  -p, --password <PW>    ghaf/admin password on the device (default: ghaf)
      --dry-run          Print what would run, touch nothing
  -h, --help             This message

Anything after `--` is passed through to ids-mirror-bench unchanged, e.g.
  -- --netem "slot 30ms 50ms packets 1024 limit 4096"
  -- --truncation off
  -- --rps 3
EOF
  exit 0
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
  --iface)
    IFACE="$2"
    shift 2
    ;;
  --mode)
    MODE="$2"
    shift 2
    ;;
  --window)
    WINDOW="$2"
    shift 2
    ;;
  --iterations)
    ITERATIONS="$2"
    shift 2
    ;;
  --bandwidth)
    BANDWIDTH="$2"
    shift 2
    ;;
  --sweep-min)
    SWEEP_MIN="$2"
    shift 2
    ;;
  --sweep-max)
    SWEEP_MAX="$2"
    shift 2
    ;;
  --sweep-step)
    SWEEP_STEP="$2"
    shift 2
    ;;
  --iperf-server)
    IPERF_SERVER="$2"
    shift 2
    ;;
  --no-iperf)
    NO_IPERF=1
    shift
    ;;
  --no-host-bench)
    NO_HOST_BENCH=1
    shift
    ;;
  -o | --out)
    OUT="$2"
    shift 2
    ;;
  -p | --password)
    PASSWORD="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help) usage ;;
  --)
    shift
    EXTRA=("$@")
    break
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
done

case "$MODE" in
ab | sweep) ;;
*)
  echo "--mode must be 'ab' or 'sweep', got '$MODE'" >&2
  exit 1
  ;;
esac

# Same merge semantics as collect-logs.sh and ghaf-hw-test: local wins per
# field, and a null in local does not blank a value set in the shared file.
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

[ "$MODE" = sweep ] && [ -z "$SWEEP_MAX" ] && {
  echo "--mode sweep requires --sweep-max (e.g. --sweep-max 900M)" >&2
  exit 1
}
[ "$MODE" = sweep ] && [ "$NO_IPERF" = 1 ] && {
  echo "--mode sweep cannot be combined with --no-iperf: the sweep measures" >&2
  echo "throughput penalty, which needs an iperf3 server." >&2
  exit 1
}

# ---------------------------------------------------------------- ssh helpers

SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSHPASS_BIN=""

# Key auth is the happy path; fall back to sshpass only when the device still
# wants a password, so a rig with the key installed never needs sshpass present.
if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "ghaf@$HOST_IP" true 2>/dev/null; then
  USE_SSHPASS=0
else
  USE_SSHPASS=1
  if command -v sshpass >/dev/null 2>&1; then
    SSHPASS_BIN=$(command -v sshpass)
  else
    SSHPASS_BIN=$(nix-shell -p sshpass --run 'command -v sshpass' 2>/dev/null | tail -1 || true)
  fi
  [ -n "$SSHPASS_BIN" ] || {
    echo "Cannot authenticate to ghaf@$HOST_IP with a key, and sshpass is not" >&2
    echo "available to supply the password. Either install your key on the" >&2
    echo "device or make sshpass reachable (nix-shell -p sshpass)." >&2
    exit 1
  }
fi

# stdin carries the sudo password; ssh auth is handled by key or by sshpass, so
# the two never contend for it.
run_remote() {
  if [ "$USE_SSHPASS" = 1 ]; then
    printf '%s\n' "$PASSWORD" | "$SSHPASS_BIN" -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "ghaf@$HOST_IP" -- "$1"
  else
    printf '%s\n' "$PASSWORD" | ssh "${SSH_OPTS[@]}" "ghaf@$HOST_IP" -- "$1"
  fi
}

# ------------------------------------------------------------------ preflight

echo "==> Preflight on $HOST_IP"

# Single-quoted on purpose: every expansion in here has to happen on the
# device, not in this shell.
# shellcheck disable=SC2016
REMOTE_PROBE=$(run_remote '
  echo "bench=$(command -v ids-mirror-bench 2>/dev/null || echo MISSING)"
  echo "unit=$(systemctl list-unit-files ids-mirror.service --no-legend 2>/dev/null | awk "{print \$2}" || echo MISSING)"
  echo "trunc=$([ -e /etc/ids-mirror/trunc.o ] && echo present || echo absent)"
  defdevs=$(ip route show default 2>/dev/null | awk "{for(i=1;i<=NF;i++) if(\$i==\"dev\") print \$(i+1)}" | sort -u | tr "\n" " ")
  for s in /sys/class/net/*; do
    n=$(basename "$s"); [ -e "$s/device" ] || continue
    [ "$n" = mirror ] && continue
    d=$(basename "$(readlink "$s/device/driver" 2>/dev/null)" 2>/dev/null || true)
    [ "$d" = virtio_net ] && continue
    ip4=$(ip -4 -o addr show dev "$n" scope global 2>/dev/null | awk "{print \$4; exit}")
    [ -z "$ip4" ] && ip4=no-address
    case " $defdevs " in *" $n "*) dr=default-route ;; *) dr=no-default-route ;; esac
    rps=$(cat "$s/queues/rx-0/rps_cpus" 2>/dev/null || echo "-")
    sp=$(cat "$s/speed" 2>/dev/null || echo "-")
    case "$sp" in "" | -1) sp="-" ;; esac
    echo "nic=$n $ip4 $dr $(cat "$s/operstate" 2>/dev/null || echo unknown) rps=$rps speed=$sp"
  done
  echo "netemraw=$(tc qdisc show dev mirror 2>/dev/null | grep -m1 "qdisc netem" || true)"
  echo "rev=$(readlink /run/current-system 2>/dev/null || echo unknown)"
') || {
  echo "Cannot reach ghaf@$HOST_IP" >&2
  exit 1
}

BENCH_PATH=$(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^bench=//p')
MIRROR_UNIT=$(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^unit=//p')
TRUNC_OBJ=$(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^trunc=//p')
DEVICE_REV=$(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^rev=//p')

# netem and rps are configured in Nix (trafficMirror.sender.netem and
# sender.rps.enable) and applied by ids-mirror's start script. Read what is
# actually deployed rather than restating the Nix defaults here: the device
# can be running an older generation than the checkout, and the point of the
# run is to measure what is on it.
NETEM_LIVE=$(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^netemraw=//p' |
  sed -e 's/^qdisc netem [^ ]* root refcnt [0-9]* //' -e 's/ seed [0-9]*//')
[ -n "$NETEM_LIVE" ] || NETEM_LIVE="none (no netem qdisc on the mirror tap)"

NIC_NAMES=()
NIC_DESC=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  NIC_NAMES+=("${line%% *}")
  NIC_DESC+=("$line")
done < <(printf '%s\n' "$REMOTE_PROBE" | sed -n 's/^nic=//p')

if [ "$BENCH_PATH" = MISSING ]; then
  echo "ids-mirror-bench is not installed on this device." >&2
  echo "It ships only on debug images (gated on ghaf.profiles.debug.enable)," >&2
  echo "and only where traffic mirroring is enabled. Flash a *-debug target." >&2
  exit 1
fi
if [ -z "$MIRROR_UNIT" ] || [ "$MIRROR_UNIT" = MISSING ]; then
  echo "ids-mirror.service does not exist on this device: passive monitoring" >&2
  echo "is off (ghaf.virtualization.microvm.idsvm.passiveMonitor.enable)." >&2
  echo "The bench would measure ON and OFF as the same thing." >&2
  exit 1
fi

echo "  bench      : $BENCH_PATH"
echo "  ids-mirror : $MIRROR_UNIT"
echo "  trunc.o    : $TRUNC_OBJ (--truncation on needs 'present')"
echo "  system     : $DEVICE_REV"

# Resolving the interface here, against what the device actually has, rather
# than trusting a name from a previous run. Interface names are not stable
# across targets or even across re-plugs -- the udev rule in netvm-base.nix
# derives ueth<N> from the interface index, so pulling the dongle bumps
# ueth5 to ueth6 -- and the bench's own fallback takes the first NIC in
# sysfs order, which is alphabetical and unrelated to which one carries
# traffic. Measuring an idle NIC produces a near-zero delta that reads
# exactly like "mirroring is free".
if [ "${#NIC_NAMES[@]}" -eq 0 ]; then
  echo "No physical NIC on the device; nothing to measure." >&2
  exit 1
fi

if [ -n "$IFACE" ]; then
  FOUND=0
  for n in "${NIC_NAMES[@]}"; do [ "$n" = "$IFACE" ] && FOUND=1; done
  if [ "$FOUND" = 0 ]; then
    echo >&2
    echo "  --iface '$IFACE' is not a physical NIC on this device." >&2
    echo "  Present:" >&2
    for d in "${NIC_DESC[@]}"; do echo "    $d" >&2; done
    exit 1
  fi
  echo "  iface      : $IFACE (given)"
elif [ "${#NIC_NAMES[@]}" -eq 1 ]; then
  IFACE="${NIC_NAMES[0]}"
  echo "  iface      : $IFACE (only physical NIC)"
else
  echo
  echo "  Several physical NICs. Measure the one carrying the traffic you care"
  echo "  about -- an idle NIC reports mirroring as free:"
  echo
  i=1
  for d in "${NIC_DESC[@]}"; do
    printf "    %d) %s\n" "$i" "$d"
    i=$((i + 1))
  done
  echo
  if [ ! -t 0 ]; then
    echo "  Not running on a terminal, so cannot ask. Pass --iface <name>." >&2
    exit 1
  fi
  while :; do
    read -r -p "  Choose [1-${#NIC_NAMES[@]}]: " CHOICE
    case "$CHOICE" in
    '' | *[!0-9]*) ;;
    *)
      if [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#NIC_NAMES[@]}" ]; then
        IFACE="${NIC_NAMES[$((CHOICE - 1))]}"
        break
      fi
      ;;
    esac
    echo "  Enter a number between 1 and ${#NIC_NAMES[@]}."
  done
  echo "  iface      : $IFACE (chosen)"
fi

# Anything the user put after `--` wins; otherwise the deployed Nix values
# stand, because passing neither flag is what leaves ids-mirror's own
# configuration in place.
OVERRIDE_NETEM=0
OVERRIDE_RPS=0
for a in ${EXTRA[@]+"${EXTRA[@]}"}; do
  case "$a" in
  --netem | --no-netem) OVERRIDE_NETEM=1 ;;
  --rps) OVERRIDE_RPS=1 ;;
  esac
done

RPS_LIVE=""
for d in "${NIC_DESC[@]}"; do
  n=${d%% *}
  m=${d##*rps=}
  RPS_LIVE="$RPS_LIVE $n=$m"
done
RPS_LIVE=${RPS_LIVE# }

if [ "$OVERRIDE_NETEM" = 1 ]; then
  echo "  netem      : overridden on the command line"
else
  echo "  netem      : $NETEM_LIVE (deployed)"
fi
if [ "$OVERRIDE_RPS" = 1 ]; then
  # apply_rps runs once, before the pair loop, while ids-mirror's start script
  # re-applies its own per-interface assignment on every ON phase -- unlike
  # netem and truncation, which the bench deliberately re-applies after each
  # start. So --rps holds only until the first pair begins.
  echo "  rps        : $RPS_LIVE (deployed)"
  echo
  echo "  WARNING: --rps is overwritten by ids-mirror at the first Mirror ON." >&2
  echo "  The bench applies it once before the loop and never re-applies it," >&2
  echo "  so the run measures the deployed assignment above, not your value." >&2
  echo "  To really change it, set trafficMirror.sender.rps.enable in Nix." >&2
  echo
else
  echo "  rps        : $RPS_LIVE (deployed)"
fi

# -------------------------------------------------- ids-bench-server preflight

# Checked before the run rather than discovered 30s into it, because a missed
# host-CPU sample is not merely missing: measure_window only appends to
# host_cpu when the query succeeded, and delta() pairs ON against OFF by line
# number. One dropped sample therefore shifts every later pair against its
# partner, and the host CPU delta comes out as a plausible-looking number
# computed from mismatched windows.
if [ "$NO_HOST_BENCH" = 0 ]; then
  echo
  echo "==> Checking ids-bench-server"
  # shellcheck disable=SC2016  # $1 is awk's field, expanded on the device
  HOST_BENCH_IP=$(run_remote 'getent hosts ghaf-host | awk "{print \$1; exit}"' 2>/dev/null | tr -d '\r' | tr -d '[:space:]')
  if [ -z "$HOST_BENCH_IP" ]; then
    echo "  Cannot resolve ghaf-host from net-vm; skipping host CPU measurement." >&2
    NO_HOST_BENCH=1
  else
    BENCH_SRV=$(run_remote "printf 'hostname\n' | nc -w 3 $HOST_BENCH_IP 9999 2>/dev/null || true" | tr -d '\r')
    if [ -z "$BENCH_SRV" ]; then
      echo "  ids-bench-server did not answer on $HOST_BENCH_IP:9999." >&2
      echo >&2
      echo "  It ships only on debug images. Check it on ghaf-host with:" >&2
      echo "    systemctl status ids-bench-server.service" >&2
      echo >&2
      echo "  Re-run with --no-host-bench to measure net-vm only." >&2
      exit 1
    fi
    echo "  answering on $HOST_BENCH_IP:9999 — $BENCH_SRV"
    # The server serves one connection and exits; systemd restarts it about a
    # second later. The probe above consumed that connection, and the bench
    # opens its own the moment it starts, so give the restart time to land --
    # otherwise the first query races it and the run begins with exactly the
    # dropped sample this check exists to prevent.
    sleep 3
  fi
fi

# --------------------------------------------------------- local iperf3 server

IPERF_PID=""
MIRROR_TOUCHED=0

# Reached only through the trap below, which shellcheck cannot see.
# shellcheck disable=SC2317,SC2329
cleanup() {
  local rc=$?
  if [ -n "$IPERF_PID" ]; then
    kill "$IPERF_PID" 2>/dev/null || true
    wait "$IPERF_PID" 2>/dev/null || true
  fi
  # The bench flips ids-mirror per pair and restarts it when it finishes
  # normally. An interrupt can land in an OFF window, which would leave the
  # device with mirroring off and nothing saying so.
  if [ "$MIRROR_TOUCHED" = 1 ] && [ "$rc" -ne 0 ]; then
    echo
    echo "==> Interrupted; restarting ids-mirror on the device"
    run_remote "sudo -S -p '' systemctl start ids-mirror" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

resolve_iperf3() {
  if command -v iperf3 >/dev/null 2>&1; then
    command -v iperf3
    return 0
  fi
  local p
  p=$(nix-shell -p iperf3 --run 'command -v iperf3' 2>/dev/null | tail -1 || true)
  [ -n "$p" ] && {
    printf '%s\n' "$p"
    return 0
  }
  return 1
}

if [ "$NO_IPERF" = 0 ] && [ -z "$IPERF_SERVER" ]; then
  # The address the device would reach us on, not our default-route address:
  # on a multi-homed workstation those differ and the device can only use the
  # one on the path it takes to us.
  IPERF_SERVER=$(ip route get "$HOST_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  [ -n "$IPERF_SERVER" ] || {
    echo "Could not work out our own address toward $HOST_IP." >&2
    echo "Pass --iperf-server explicitly, or --no-iperf." >&2
    exit 1
  }

  IPERF3_BIN=$(resolve_iperf3) || {
    echo "iperf3 not available locally (tried PATH and nix-shell -p iperf3)." >&2
    echo "Pass --iperf-server <host> to use one elsewhere, or --no-iperf." >&2
    exit 1
  }

  if [ "$DRY_RUN" = 0 ]; then
    # Reuse a listener that is already up instead of colliding with it: a
    # previous run or a hand-started server is perfectly usable, and only a
    # server this script started is torn down at the end (IPERF_PID stays
    # empty otherwise, so cleanup leaves someone else's process alone).
    if "$IPERF3_BIN" -c "$IPERF_SERVER" -t 1 -b 1M >/dev/null 2>&1; then
      echo "==> Reusing the iperf3 server already on $IPERF_SERVER:5201"
    else
      echo "==> Starting local iperf3 server on $IPERF_SERVER:5201"
      "$IPERF3_BIN" -s >/dev/null 2>&1 &
      IPERF_PID=$!
      sleep 1
      kill -0 "$IPERF_PID" 2>/dev/null || {
        IPERF_PID=""
        echo "Could not start an iperf3 server, and nothing usable answers on" >&2
        echo "$IPERF_SERVER:5201. Look for a stale process holding the port:" >&2
        echo "  ss -tlnp | grep 5201" >&2
        exit 1
      }
    fi
  fi
fi

# ----------------------------------------------------------------- run

BENCH_ARGS=()
[ -n "$IFACE" ] && BENCH_ARGS+=(--iface "$IFACE")
[ -n "$WINDOW" ] && BENCH_ARGS+=(--window "$WINDOW")
[ -n "$ITERATIONS" ] && BENCH_ARGS+=(--iterations "$ITERATIONS")
[ -n "$IPERF_SERVER" ] && BENCH_ARGS+=(--iperf-server "$IPERF_SERVER")
[ "$NO_HOST_BENCH" = 0 ] && BENCH_ARGS+=(--host-bench)
if [ "$MODE" = sweep ]; then
  BENCH_ARGS+=(--sweep --sweep-max "$SWEEP_MAX")
  [ -n "$SWEEP_MIN" ] && BENCH_ARGS+=(--sweep-min "$SWEEP_MIN")
  [ -n "$SWEEP_STEP" ] && BENCH_ARGS+=(--sweep-step "$SWEEP_STEP")
else
  [ -n "$BANDWIDTH" ] && BENCH_ARGS+=(--bandwidth "$BANDWIDTH")
fi
[ ${#EXTRA[@]} -gt 0 ] && BENCH_ARGS+=("${EXTRA[@]}")

# printf %q quotes for the remote bash, which matters for values with spaces
# such as --netem "slot 10ms 20ms packets 300 limit 2000".
QUOTED=$(printf '%q ' "${BENCH_ARGS[@]}")
REMOTE_CMD="sudo -S -p '' ids-mirror-bench $QUOTED"

# Rough ETA so a sweep that will take hours says so before it starts.
W="${WINDOW:-30}"
N="${ITERATIONS:-10}"
if [ "$MODE" = sweep ]; then
  STEPS=$(awk -v mn="${SWEEP_MIN:-${SWEEP_STEP:-5M}}" -v mx="$SWEEP_MAX" -v st="${SWEEP_STEP:-5M}" \
    'function n(v){u=substr(v,length(v));x=v+0;if(u=="G"||u=="g")return x*1000;if(u=="K"||u=="k")return x/1000;return x}
     BEGIN{printf "%d", int((n(mx)-n(mn))/n(st))+1}')
  ETA=$(((STEPS * N * 2 * W) + (STEPS * N * 2) + (2 * W)))
else
  ETA=$(((N * 2 * W) + (N * 2)))
fi

[ -z "$OUT" ] && OUT="ghaf-bench/$(date +%Y%m%d-%H%M%S)"

echo
echo "==> Run"
echo "  mode       : $MODE"
echo "  iperf3     : ${IPERF_SERVER:-none}"
echo "  output     : $OUT"
echo "  ETA        : ~$((ETA / 60)) min ($ETA s)"
echo "  remote cmd : ids-mirror-bench $QUOTED"
echo

if [ "$DRY_RUN" = 1 ]; then
  echo "(dry run -- nothing executed)"
  exit 0
fi

mkdir -p "$OUT"
{
  echo "date:        $(date -Is)"
  echo "device_ip:   $HOST_IP"
  echo "machine:     ${MACHINE:-<none>}"
  echo "device_rev:  $DEVICE_REV"
  echo "repo_rev:    $(git rev-parse HEAD 2>/dev/null || echo unknown)$([ -n "$(git status --porcelain 2>/dev/null)" ] && echo ' (dirty)')"
  echo "mode:        $MODE"
  echo "iface:       ${IFACE:-<auto>}"
  echo "phys_nics:   ${NIC_NAMES[*]}"
  echo "netem:       $([ "$OVERRIDE_NETEM" = 1 ] && echo "overridden via --" || echo "$NETEM_LIVE (deployed)")"
  echo "rps:         $RPS_LIVE (deployed)"
  echo "iperf3:      ${IPERF_SERVER:-none}"
  echo "trunc_obj:   $TRUNC_OBJ"
  echo "bench_args:  $QUOTED"
} >"$OUT/manifest.txt"

MIRROR_TOUCHED=1
set +e
run_remote "$REMOTE_CMD" 2>&1 | tee "$OUT/output.txt"
RC=${PIPESTATUS[0]}
set -e

echo
if [ "$RC" -eq 0 ]; then
  echo "==> Done. Results in $OUT/"
else
  echo "==> Bench exited $RC. Partial output in $OUT/output.txt" >&2
fi
exit "$RC"
