---
name: ghaf-logs
description: Collect journals and unit state from every VM on a Ghaf device, and diff two snapshots to separate a regression from noise that was always there. Use this whenever something broke on a device after a change, flash or update, when asked what went wrong, why a VM or service failed, whether a change regressed anything, or to check the logs, journal or systemd state of ghaf-host or any VM. Also use it before proposing a fix for any runtime failure, so the diagnosis rests on evidence rather than a guess.
---

# Ghaf log collection and regression hunting

A Ghaf device logs from a dozen places at once. Two problems follow: the evidence you need
is scattered across VMs, and a healthy boot already contains plenty of errors. This skill
solves both — snapshot everything, then compare against a known-good snapshot so the only
thing you read is what actually changed.

Read `ghaf-target` for the address map. Analysis belongs to the `ghaf-log-triage` agent —
hand it the snapshot rather than reading tens of thousands of journal lines yourself.

## Take a snapshot

```bash
.claude/skills/ghaf-logs/scripts/collect-logs.sh --machine darter-pro
.claude/skills/ghaf-logs/scripts/collect-logs.sh --ip 192.168.1.50 --out ghaf-logs/after-fix
.claude/skills/ghaf-logs/scripts/collect-logs.sh --machine Orin-AGX --password ghaf
```

It asks the device which VMs exist (`microvm@*` units plus `/etc/hosts`) rather than
assuming a fleet, collects in parallel over one multiplexed ssh connection, and writes:

```
<dir>/manifest.txt        when, where, repo rev, and the deployed store path per VM
<dir>/ghaf-host/          journal, failed units, dmesg, /proc/cmdline, microvm units
<dir>/<vm>/               journal, failed units, running system
<dir>/<vm>/UNREACHABLE.txt   present when that VM did not answer
```

Other flags worth knowing: `--vms "gui-vm net-vm"` narrows the fleet when you already know
where to look, and `--prev-boot` also collects `journalctl -b -1`, which is the only way to
read a boot the device has since left behind — reach for it after any crash or reboot,
because the current boot is by definition the one that came *after* the problem.

A VM that should be there and isn't is a finding in itself, so the collector records absence
instead of failing. But read a wall of `UNREACHABLE.txt` as a question, not an answer:

- **Every VM unreachable at once** is far more often ssh than a dead fleet. Two mechanisms
  both produce it, and both are described in `ghaf-target` — a `known_hosts` collision across
  devices sharing `192.168.100.0/24`, and a control-socket collision that lands the hop on a
  different machine entirely. The collector now defends against both, so if you see this from
  a hand-written `ssh` command instead, that is the first thing to check.
- **Every VM unreachable on an Orin** is usually the missing `--password`. Inter-VM ssh there
  wants a password rather than a key, and a `BatchMode` hop can never supply one. Pass
  `--password ghaf` (needs `sshpass`) and the same fleet answers normally.

The distinction matters because "the whole device is down" and "I authenticated wrongly"
lead to completely different next moves, and only one of them is usually true.

**Keep a known-good snapshot.** Take one when the device is healthy, before you change
anything. Without a baseline you are reduced to guessing which of the errors on screen
matter, which is exactly the trap this skill exists to avoid.

## Diff against the baseline

```bash
.claude/skills/ghaf-logs/scripts/diff-logs.py ghaf-logs/known-good ghaf-logs/after-fix
```

The diff normalises timestamps, PIDs, store hashes, UUIDs, MACs and addresses before
comparing, because those vary between boots without meaning anything and would otherwise
make every line look new. It leads with units that fail now but didn't before — usually the
headline — then new journal lines, filtered to things that look like problems. `--all`
shows everything; `--max-per-file` raises the cap, and any lines it drops are counted, not
silently hidden.

Exit status is 1 when it finds something, so an unattended loop can branch on it.

## When central logging is enabled

Ghaf can forward journals to a collector rather than leaving them on each VM
(`modules/common/logging/`): clients run `systemd-journal-upload`, and the server writes to
`/var/log/journal/remote/` on admin-vm. When that is on, admin-vm holds a single
cross-VM timeline, which is the fastest way to see ordering *between* VMs:

```bash
ssh ghaf@<host_ip> -- ssh admin-vm \
  journalctl -D /var/log/journal/remote --no-pager --since -30min
```

Prefer per-VM collection for depth and the aggregated journal for ordering. The aggregated
view can lag or drop entries if the network was part of the failure, so do not treat its
silence as proof that nothing happened.

## Reading the result

Hand the snapshot directory to the `ghaf-log-triage` agent. It returns ranked findings with
the VM, unit, first occurrence and a suspected module path — you get the conclusions rather
than the journal.

When you are reading a snapshot yourself instead — one VM, one unit, a question you can
already frame — `references/vm-map.md` is the attribution table: which VM owns which
subsystem, and which failure signature maps to which module area. It saves guessing at
whether a PipeWire error belongs to audio-vm or the desktop.

Two habits that repeatedly matter:

- **Earliest, not loudest.** systemd reports a failed unit long after the thing that made
  it fail. The first error inside that unit's own logs is the one to read.
- **Confirm what is actually running.** `manifest.txt` records each VM's
  `/run/current-system`. If that store path is in your local store you can read the exact
  generated configuration — `/nix/store/<hash>-nixos-system-<vm>-*/etc/` — instead of
  re-deriving what you assume the Nix produced. This is how the greetd PAM regression was
  pinned down: the rendered `etc/pam.d/greetd` settled in seconds what the module source
  had made ambiguous.
