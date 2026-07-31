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
