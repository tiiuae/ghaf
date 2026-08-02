---
name: ghaf-connect
description: Get a shell or console on a Ghaf device or one of its VMs - over ethernet when it is up, over serial when it is not. Use this whenever a device is unreachable, unresponsive, stuck at boot, hung after a flash, or when you need to run a command on ghaf-host or a named VM (gui-vm, net-vm, admin-vm, audio-vm, an appvm). Also use it when the user says the device "won't come up", "isn't responding", "is bricked", or asks to check whether it is alive.
---

# Reaching a Ghaf device

Two transports, and the choice is not a preference — it is a diagnosis. Ethernet means
the device booted far enough to bring up net-vm and sshd. Serial is what you have when it
didn't. Read `ghaf-target` first for the address map and config location.

## Decide which transport you need

Try ethernet first; it is faster and gives you every VM. Escalate to serial when ethernet
fails, because *how* it fails is itself evidence:

| Symptom | What it suggests | Next step |
|---|---|---|
| ssh connects, VMs reachable | device is healthy | carry on over ethernet |
| ssh refused / no route | net-vm down, or NIC not passed through | serial; check host boot and `microvm@net-vm.service` |
| ssh times out, no link on `usb_iface` | device off, wedged, or not enumerated | serial; check power and cable |
| ssh works but a VM name won't resolve | that microVM failed to start | ethernet is fine — go straight to `ghaf-logs` on ghaf-host |

## Over ethernet

The device's external address belongs to net-vm; everything else is one hop in.

```bash
ping -c2 <host_ip>
ssh -o ConnectTimeout=5 ghaf@<host_ip> -- true && echo reachable
ssh ghaf@<host_ip> -- ssh ghaf-host systemctl --failed
ssh ghaf@<host_ip> -- ssh gui-vm journalctl -b -u greetd --no-pager
```

If the link itself is suspect, check the host side before blaming the device — the
interface facing it is `usb_iface` in the config, usually `ghaf-usb`:

```bash
ip -br link show ghaf-usb
ip -br addr show ghaf-usb
```

A USB-ethernet adapter that renumbered or a cable in the wrong port accounts for a good
share of "the device is dead" reports, and costs seconds to rule out.

Two more before you escalate, both consequences of every device sharing `192.168.100.0/24`
and both detailed in `ghaf-target`. If *every* VM refuses at once, a `known_hosts` entry from
another device is a likelier explanation than a fleet-wide failure — retry with
`-o UserKnownHostsFile=/dev/null`. And if the hops succeed but what they report makes no
sense for this hardware, a stale ssh control socket may be serving you a different device
entirely; `uname -m` on the far end settles it in one command. Ruling these out first is
cheap, and both otherwise send you to serial for a device that was never unwell.

## Over serial

Use `scripts/serial-console.sh`. It reads `serial_device` and `serial_baud` from the shared
config, warns when another process already holds the port, and has a non-interactive
capture mode:

```bash
# Capture boot output — do this BEFORE power-cycling, so you catch the failure itself
.claude/skills/ghaf-connect/scripts/serial-console.sh -m Orin-AGX -c 180

# Interactive session
.claude/skills/ghaf-connect/scripts/serial-console.sh -d /dev/ttyUSB0 -b 115200
```

Prefer `--capture` when you are gathering evidence rather than driving the device. It needs
only coreutils, produces a log file you can hand to `ghaf-log-triage`, and does not require
a terminal you can type into.

Serial availability is per-device: Jetsons expose a console on the micro-USB cable, laptops
generally need a USB-serial adapter and may expose nothing at all. Read the config; do not
assume a node exists. If `serial_device` is null and no `/dev/ttyUSB*` or `/dev/ttyACM*` is
present, say so plainly rather than guessing a path.

### Running commands over serial

`serial-console.sh` captures what the device says. `scripts/serial-run.sh` **drives** it —
logs in and runs a command list — which is what you need when the device is up but has no
network:

```bash
.claude/skills/ghaf-connect/scripts/serial-run.sh -m Orin-AGX \
  'systemctl --failed' 'ip -br addr' 'journalctl -b -u microvm@net-vm.service | tail -30'
```

This is the only way in when net-vm is down, and that is not a rare case: a failed NIC
passthrough, a merged IOMMU group or a bad firewall rule all leave a perfectly healthy
machine that no ssh-based tool here can reach. It matters most straight after an install —
a device that flashed or netbooted successfully and then failed to start net-vm looks
identical from outside to one that never booted, and only the console separates the two.

It logs in with the debug image's account (`ghaf`/`ghaf`, from
`modules/reference/personalize/accounts.nix`; override with `GHAF_SERIAL_USER` /
`GHAF_SERIAL_PASSWORD`). A release image will refuse them.

Two limits before you trust the output. It uses **fixed sleeps, not prompt detection** — a
command slower than its slot gets truncated, so raise `-s`/`GHAF_SERIAL_STEP` rather than
concluding it produced nothing. And **the target's exit statuses are not propagated**; append
`; echo rc=$?` when you need one. A serial console is a byte stream, not a session, and
treating it as one is how you get a tool that lies quietly.

All three of these scripts — `serial-run.sh`, `serial-console.sh` and `ghaf-logs`'
`collect-logs.sh` — merge `config.local.yaml` over `config.yaml`, matching
`get_device_config()` in `.github/skills/ghaf-hw-test/ghaf-hw-test`: local wins per field,
and a `null` in the local file does **not** blank a real value in the base. That matters
because the desk-specific fields — `serial_device`, `host_ip`, `flash_drive` — are null in
the shared config by design, so a reader that ignores the local file resolves them to null
and reports "not configured" for hardware that is sitting right there.

## Sequencing a rescue

When a device is unresponsive after a flash or deploy, the order matters — the evidence
you want is destroyed by the fix:

1. Attach serial and start `--capture` **first**.
2. Power-cycle only then, so the capture contains the whole boot.
3. Read the capture for the earliest failure, not the loudest one.
4. Once networking returns, switch to `ghaf-logs` for the full picture across VMs; serial
   only ever shows you the host console.

If the capture is empty, that is informative too: no output at all usually means wrong baud,
wrong node, or a device with no power — not a kernel that died silently.
