---
name: ghaf-deploy
description: Get a built Ghaf change onto a device - by nixos-rebuild when that is sufficient, by flashing an image when it is not - then reboot, wait for it to come back, and confirm what is actually running. Use whenever asked to deploy, flash, install, update or push a change to a Ghaf device, to reflash a laptop or Jetson, or after building an image that needs to go on hardware. Also use when deciding whether a change can be switched or needs a full flash.
---

# Deploying to a Ghaf device

Two paths, and choosing wrong is expensive in opposite directions: flashing when a switch
would do wastes half an hour per iteration, while switching when a flash was needed leaves
a device that quietly disagrees with your source tree.

Read `ghaf-target` for addresses. Flashing is destructive — see the safety section before
running it unattended.

## Decide which path

```bash
.claude/skills/ghaf-deploy/scripts/needs-reflash.sh                 # uncommitted changes
.claude/skills/ghaf-deploy/scripts/needs-reflash.sh <deployed-rev>  # vs what is on the device
```

The baseline ref is the `repo_rev` recorded in a `ghaf-logs` snapshot manifest, so the
question it answers is precisely "can what I changed since that device was last deployed go
out with a switch?". Exit status is 0 for rebuild, 1 for reflash, so a loop can branch on it.

It reports reflash for partitioning, boot and secure boot, hardware definitions, kernel and
cmdline, microVM topology, and the image builders — the things `nixos-rebuild switch`
provably cannot apply to a running system.

## Path 1: rebuild (minutes)

`ghaf-rebuild` wraps `nixos-rebuild` with the ssh topology already set up. Note the
positional form — the first argument is the **net-vm it proxy-jumps through**, and it
targets `root@ghaf-host`:

```bash
nix develop --command ghaf-rebuild ghaf-usb .#intel-laptop-debug switch
nix develop --command ghaf-rebuild ghaf-usb .#intel-laptop-debug --force-local switch
nix develop --command ghaf-rebuild <netvm-ip> .#intel-laptop-debug switch   # also works
```

**Pass an ssh_config host alias, not a bare IP, whenever one exists.** ssh matches `Host`
blocks against the name *as written on the command line*, never the resolved address, so an
IP matches only `Host *` and picks up no `IdentityFile` — it then falls back to your default
keys. Where those are FIDO2/YubiKey-backed, the jump hop demands a touch per connection or
fails outright, while the second hop (`root@ghaf-host`, an alias) quietly works, which makes
the failure look like a device problem rather than a key-selection one. Check what ssh will
actually use before blaming the device:

```bash
ssh -G root@192.168.10.135 | grep -i identityfile   # default keys — no alias matched
ssh -G ghaf-usb            | grep -i identityfile   # the key the alias specifies
```

`--force-local` builds here (`--builders ""`), `--force-remote` pushes to the builders
(`--max-jobs 0`), `--insecure` skips host key checking on both hops. It captures the
previous system from `/nix/var/nix/profiles/system` and prints an `nvd` package diff when
the target has `nvd`, which is the fastest way to see what your switch actually changed.

**A host switch does not restart the microVMs.** They keep running their old configuration
until their unit is restarted — this is the single most common way to conclude a fix didn't
work when it was simply never applied:

```bash
ssh ghaf@<host_ip> -- ssh ghaf-host sudo systemctl restart microvm@gui-vm.service
```

That is the pattern ghaf itself uses (`modules/common/services/power.nix`). Restart only the
VMs your change touched; reboot the device if you changed something host-wide or are unsure.

## Path 2: flash (tens of minutes, destructive)

```bash
nix build .#intel-laptop-debug
sudo nix develop --command ghaf-flash -d /dev/sdX -i result/ghaf-image.raw.zst
```

`flash-script` takes `-d <disk> -i <image>`, plus `-f` to skip confirmation, `-n` for
non-interactive progress lines (no TTY), and `-p <secs>` for the progress interval. It must
run as root. It picks up `result/ghaf-image.bmap` automatically when the sibling file is
present, which makes the write substantially faster — you do not pass it.

Jetsons flash over USB in recovery mode instead:

```bash
nix build .#nvidia-jetson-orin-agx-debug-from-x86_64-flash-script
sudo ./result/bin/flash-ghaf          # or flash-ghaf-host for -luks- targets
```

### Before writing to a disk

Getting this wrong destroys the wrong drive, so confirm rather than trust:

```bash
lsblk -o NAME,SIZE,TYPE,RM,MODEL,MOUNTPOINTS /dev/sdX
```

Check it is the size you expect, `RM` is 1 for removable media, the model matches the stick
you plugged in, and nothing on it is mounted. Cross-check against `flash_drive` in the
device config. If the config says one device and the user says another, stop and ask —
device nodes renumber between reboots, and `/dev/sda` is a system disk on plenty of machines.

## After deploying

Wait for it to come back, then confirm what is actually running rather than assuming:

```bash
until ssh -o ConnectTimeout=5 -o BatchMode=yes ghaf@<host_ip> -- true 2>/dev/null; do sleep 5; done
ssh ghaf@<host_ip> -- ssh ghaf-host readlink /run/current-system
ssh ghaf@<host_ip> -- ssh gui-vm readlink /run/current-system
```

Compare that store path against what you built. A mismatch means the switch went to a
different generation, the VM was not restarted, or the device booted an older entry — all
of which look identical to "my fix didn't work" until you check.

Take a `ghaf-logs` snapshot immediately after a deploy, while the state is fresh. If you
have a baseline from before, the diff tells you what your change did to the system rather
than what the system happens to log.

If the device does not come back at all, go to `ghaf-connect` and capture serial before
power-cycling — the boot that failed is the evidence, and a power cycle destroys it.
