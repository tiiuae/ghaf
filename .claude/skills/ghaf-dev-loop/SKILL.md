---
name: ghaf-dev-loop
description: Run the full Ghaf hardware development cycle - build, deploy, wait for boot, collect logs, triage regressions, propose a fix, repeat - unattended, with a stop file and guard rails around the destructive steps. Use when asked to iterate on a device until something works, to run a build-flash-test loop, to fix a hardware failure end to end, or to keep going until the tests pass. Also use to set up or reason about that loop even for a single iteration.
---

# The Ghaf development loop

This ties the other skills into one cycle. It runs unattended by design, which means the
guard rails are the important part: a loop that flashes is the one thing here that can
leave a device unbootable, and a loop that "fixes" without understanding produces a tree of
plausible edits that each broke something else.

## The cycle

1. **Decide the deploy path** — `ghaf-deploy`'s `needs-reflash.sh` against the rev the
   device is running (from the last snapshot's `manifest.txt`).
2. **Build** — `ghaf-build`. Check `--dry-run` first if the change looks deep.
3. **Deploy** — rebuild, or flash if step 1 said so. Restart the microVMs your change
   touched; a host switch alone leaves them on the old configuration.
4. **Wait for boot** — poll ssh until it answers, bounded by the device's
   `boot_wait_seconds`. If it never comes back, capture serial before power-cycling.
5. **Collect** — `ghaf-logs` snapshot into this iteration's directory.
6. **Compare** — `diff-logs.py` against the last known-good snapshot. Exit 1 means new
   problems; exit 0 means nothing new, which is a result worth stating.
7. **Test** — `ghaf-test` with the tag that matters, full suite once it passes.
8. **Triage** — hand the snapshot to `ghaf-log-triage`. Reconcile its findings with the
   test failures before touching code.
9. **Fix, or stop** — see below.

## Before every destructive step

Destructive means flashing, power-cycling, or committing. Check, in this order:

```bash
[ -f /tmp/ghaf-loop-stop ] && { echo "stop file present — halting"; exit 0; }
```

The stop file (`fix_loop.stop_file` in the device config) is the kill switch: `touch
/tmp/ghaf-loop-stop` from any terminal and the loop halts before it next touches the device,
without needing to find and kill a process mid-write.

Then, for a flash specifically: verify the target drive against `flash_drive` in the config
*and* against `lsblk` (removable, expected size, nothing mounted), and print what is about
to be erased. Never flash a tree whose uncommitted changes were not part of the build you
are about to deploy — the device would end up running something no revision describes.

## Record every iteration

Without this you cannot tell which change produced which result, and after three iterations
nobody can reconstruct the sequence:

```
iteration-<N>/
  rev.txt          git rev + whether the tree was dirty
  deployed.txt     store path actually running, per VM
  logs/            the snapshot
  diff.md          diff-logs.py output against the baseline
  test/            output.xml and the parsed summary
  change.diff      what was edited this iteration, if anything
```

## When to stop

- **The tests pass and the diff is clean.** Done — say which tag passed, since a green
  `pre-merge` is not a green `gui`.
- **Iteration cap reached** (`fix_loop.max_iterations`, default 5). Stop and report where it
  got to; do not silently raise the cap.
- **The same failure survives three fixes.** Stop. Three failed attempts usually means the
  diagnosis is wrong, not the fix — re-read the earliest failure in the logs rather than
  attempting a fourth variation. Ghaf failures cascade across VMs, and a fix aimed at a
  downstream symptom can look almost right for a long time.
- **The device stopped answering and serial shows nothing.** Stop and ask for hands.
  Nothing this loop can do next is safe.

## Proposing fixes

The loop may edit code, but the standard is the same as any other change: find the cause
before writing the fix. Evidence for a Ghaf runtime failure usually means the rendered
artifact rather than the module source — the deployed `/nix/store/<hash>-nixos-system-*/etc/`
settles in seconds what module source can leave ambiguous, and every skill here records the
deployed store path so you can read it.

Make one change per iteration. Bundling three plausible fixes and getting a green run tells
you nothing about which one mattered, and leaves two unexplained edits in the tree.

## Using the existing bash loop

`.github/skills/ghaf-hw-test/ghaf-hw-test run --device <name> --ip <IP> --fix-loop -y
[--drive /dev/sdX]` already implements test → analyze → build → flash → wait → retest with
its own iteration cap. It is a reasonable engine when the cycle is exactly that shape.

Drive the steps yourself when you need what it does not do: log collection across VMs,
regression diffing against a baseline, serial capture when the device does not return, or
any judgement about *which* fix to make. Without `--drive`/`--recovery` it skips build and
flash entirely, which is the right mode when you are deploying with `ghaf-rebuild`.
