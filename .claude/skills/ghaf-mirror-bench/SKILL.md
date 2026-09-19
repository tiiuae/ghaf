---
name: ghaf-mirror-bench
description: Measure what IDS traffic mirroring costs on a Ghaf device - CPU, RAM, latency and throughput, with mirroring on versus off. Use when asked to benchmark the mirror, quantify IDS or passive-monitoring overhead, check whether mirroring slows the network, sweep overhead against bandwidth, or tune netem/RPS/truncation for the mirror tap. Also use before claiming mirroring is or is not expensive, so the number comes from a measurement rather than an impression.
---

# Benchmarking IDS traffic mirroring

net-vm clones physical NIC traffic to ids-vm over a GRE tunnel (`tc mirred`). This skill
measures what that costs. The tool is `ids-mirror-bench`, which ships on the device;
`scripts/run-mirror-bench.sh` drives it from here and supplies the three things it cannot
provide itself — an iperf3 server, root on net-vm, and somewhere to keep the output.

Read `ghaf-target` for addresses. The architecture being measured is in
`modules/microvm/common/traffic-mirror.nix`.

## Why it interleaves

The bench does not run "mirror on for five minutes, then off for five minutes". It
alternates ON and OFF in short windows and pairs them up. Wi-Fi fading, thermal throttling
and background load all drift on a scale of minutes, and a straight before/after comparison
attributes that drift to mirroring. Interleaving cancels it: each ON window is compared
against an OFF window taken seconds later under the same conditions.

That is also why the delta column, not the absolute numbers, is the result.

## Run it

The interface is not in these commands on purpose — the script asks, see below.

```bash
# A/B, default 10 pairs × 30s — the normal first move
.claude/skills/ghaf-mirror-bench/scripts/run-mirror-bench.sh --ip <netvm-ip>

# See what it would do, touch nothing (also prints the preflight)
.claude/skills/ghaf-mirror-bench/scripts/run-mirror-bench.sh --ip <netvm-ip> --dry-run

# Bandwidth sweep with plots
.claude/skills/ghaf-mirror-bench/scripts/run-mirror-bench.sh --ip <netvm-ip> \
  --mode sweep --sweep-max 900M --sweep-step 50M
```

`--machine <name>` reads the address from `config.local.yaml` instead of `--ip`. Anything
after `--` goes to `ids-mirror-bench` untouched:

```bash
... -- --netem "slot 30ms 50ms packets 1024 limit 4096"
... -- --truncation off
... -- --flood
```

(`--rps` is also accepted but does not survive the first pair — see below.)

The script starts an `iperf3 -s` here, works out which of our addresses the device reaches
us on (not our default-route address — on a multi-homed workstation those differ), runs the
bench over ssh, writes `output.txt` and a `manifest.txt` recording the device generation and
repo rev, and tears the server down afterwards.

## Which interface

This is the choice that most often invalidates a run, so the script resolves it against the
device instead of trusting a name. One physical NIC is picked automatically; several and it
asks, showing what distinguishes them:

```
    1) ueth5 192.168.10.188/24 default-route up
    2) wlp0s5f0 192.168.1.4/24 default-route up
```

Pick the NIC on the path the traffic actually takes — with the iperf3 server on
`192.168.10.1`, that is `ueth5` above. Measuring the idle one yields a delta near zero,
which reads exactly like "mirroring is free". `ids-mirror-bench` on its own falls back to
the first NIC in sysfs order, which is alphabetical and unrelated to that.

**Do not carry a remembered interface name between runs.** The udev rule in
`netvm-base.nix` derives `ueth<N>` from the interface index, so unplugging and replugging a
dongle turns `ueth5` into `ueth6`, and names differ across targets anyway. `--iface` is
still there for scripted runs and is validated against the device — a stale name is
rejected with the real list rather than silently measuring something else. Without a
terminal to ask on, the script refuses rather than guessing.

## netem and RPS come from Nix

Both are configured in `modules/microvm/common/traffic-mirror.nix` and applied by
`ids-mirror`'s start script, so the default for a run is **whatever the device has
deployed** — passing neither flag is what leaves that configuration in place:

| Setting | Nix option | Default |
|---|---|---|
| netem on the mirror tap | `trafficMirror.sender.netem` | `slot 10ms 20ms packets 300 limit 2000` |
| RPS on mirrored NICs | `trafficMirror.sender.rps.enable` | `true` — one distinct CPU per NIC, round-robin |

The script reads both off the device during preflight and prints them, rather than
restating the Nix defaults, because a device can be running an older generation than the
checkout:

```
  netem      : limit 2000 slot 10ms 20ms packets 300 (deployed)
  rps        : ueth5=1 wlp0s5f0=2 (deployed)
```

Override either by passing it through: `-- --netem "slot 30ms 50ms packets 1024 limit 4096"`.

**`--rps` does not survive the run.** `ids-mirror-bench` applies it once before the pair
loop and never re-applies it, while `ids-mirror`'s start script re-asserts its own
per-interface assignment on every Mirror ON — unlike netem and truncation, which the bench
deliberately re-applies after each start for exactly this reason. So `--rps off` or
`--rps 3` shows up in the bench's own header (read before the first pair) and is then
undone, and the run measures the deployed assignment. The script warns when you pass it.
Changing RPS for real means `trafficMirror.sender.rps.enable` in Nix and a redeploy.

## What has to be true first

Both halves are gated on `ghaf.profiles.debug.enable`, so **a release image cannot be
benchmarked at all**:

| Piece | Where | What it does |
|---|---|---|
| `ids-mirror-bench` | net-vm, `systemPackages` | the benchmark; needs root |
| `ids-bench-server` | ghaf-host, port 9999 | host-side CPU sampling for `--host-bench` |
| `/etc/ids-mirror/trunc.o` | net-vm | only when built with `sender.snaplen` set |

`ids-mirror.service` must also exist — that is passive monitoring being enabled
(`idsvm.passiveMonitor.enable`). Without it the bench measures ON and OFF as the same
thing and reports an honest, meaningless zero. The script checks all of this up front and
says which one is missing rather than letting the run produce numbers about nothing.

`--truncation on` needs `/etc/ids-mirror/trunc.o`, which exists only if the system was
built with a snaplen. It is a runtime attach/detach of an already-compiled eBPF filter, not
a way to set snaplen without rebuilding.

## Reading the result

```
  Metric                        Mirror ON             Mirror OFF            Delta
  CPU usage / net-vm (%):       14.20 ± 0.80          11.90 ± 0.70          +2.30%
  CPU usage / host (%):         ...
  TX throughput (Mbps):         ...
  Latency avg (ms):             ...
  RAM used (MiB):               ...
  iperf3 BW (Mbps):             ...
  Mirror tap TX (info, Mbps):   412.50 ± 9.10
```

Delta is OFF → ON, so positive means mirroring costs that much. `±` is stddev across pairs:
a delta smaller than the stddev is noise, not a measurement, and the fix is more
`--iterations`, not a firmer conclusion.

**Check `Mirror tap TX` before believing any delta.** It is how much traffic actually went
down the mirror tap during the ON windows. Near zero there means mirroring was not carrying
anything — wrong `--iface`, or the tap never came up — and every other delta on the page is
then a comparison of two identical states rather than evidence that mirroring is cheap.

## Sweep mode

`--mode sweep` walks iperf3's target bandwidth from `--sweep-min` to `--sweep-max` and plots
CPU/RAM overhead and throughput penalty against it, as ASCII charts. Use it to find where
overhead starts to bend rather than to get one number.

It costs `steps × iterations × 2 × window` seconds — the script prints an ETA before
starting, and a full-range sweep at default settings runs for hours. Narrow the range or
drop `--iterations` for a first look. It requires iperf3; `--no-iperf` is rejected for this
mode because throughput penalty is most of what it plots.

## `bench-server unreachable` invalidates the run — stop and restart it

```
  Pair 1/10 — Mirror ON...
  [warn] bench-server unreachable (192.168.100.2:9999)
```

The bench prints this and **keeps going**, which is the trap: the run completes, prints a
host CPU delta, and that number is wrong rather than missing. `measure_window` appends to
`host_cpu` only when the query succeeded, and `delta()` pairs ON against OFF by line number
— so one dropped sample shifts every later pair against its partner. Kill the run; the
result is contaminated.

The cause is usually not a dead service. `ids-bench-server` serves **one connection and
exits**, and systemd restarts it about a second later (`Restart=always`, `RestartSec=1s`),
so back-to-back queries land in the restart gap. Measured on an X1: four queries four
seconds apart all answered; three queries back-to-back answered only the first. The bench's
own header asks `hostname` and then immediately `irqbalance`, so the second one is already
racing before the first pair begins.

Two tells that this is what happened, both visible in the header before any pair runs:

- `Target :` is present (the `hostname` query won the race) but the `irqbalance` line shows
  only `net-vm=...` with no `host=...` (the second query lost it).

`systemctl restart ids-bench-server` therefore buys one more query, not a fixed run. What
works is spacing the first query away from the restart: `run-mirror-bench.sh` probes the
server during preflight, refuses to start the long run if it is genuinely unreachable, and
waits for the restart to land before launching the bench. Running the bench by hand skips
all of that.

`--no-host-bench` (script) or dropping `--host-bench` (bench) measures net-vm only, which is
the honest option when the host figure is not what you are after.

## Things that bite

- **An interrupted run can leave mirroring off.** The bench flips `ids-mirror` per pair and
  only restarts it when it finishes normally, so a Ctrl-C landing in an OFF window leaves
  the device quietly unmonitored. The script restarts it on a failed or interrupted exit;
  if you run the bench by hand instead, check `systemctl is-active ids-mirror` afterwards.
- **`--netem` and `--truncation` have to be re-applied after every ON.** `ids-mirror`'s
  start script re-attaches its own build-time state each time it starts, silently undoing
  them after the first pair. `ids-mirror-bench` already does this; a hand-rolled loop
  around `systemctl start ids-mirror` will not.
- **sudo on net-vm wants a password** (debug default `ghaf`, override with `--password`).
  The script feeds it over stdin; ssh auth is separate, by key if your key is installed and
  by sshpass otherwise.
- **The iperf3 server's placement is part of the measurement.** Run on this workstation it
  crosses the same uplink being mirrored, which is what you want for uplink overhead. A
  server reached over a different path measures a different thing — `--iperf-server` exists
  for when that is deliberate.
- **`--flood` reports no latency or loss**, by design: it pushes packets at maximum rate, so
  those columns come back `N/A` and only CPU, RAM and throughput mean anything.
