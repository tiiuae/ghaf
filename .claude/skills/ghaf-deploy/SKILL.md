---
name: ghaf-deploy
description: Get a built Ghaf change onto a device - by nixos-rebuild when that is sufficient, by flashing an image when it is not, or by netboot/PXE when you want the same install without USB media - then reboot, wait for it to come back, and confirm what is actually running. Use whenever asked to deploy, flash, install, update or push a change to a Ghaf device, to reflash a laptop or Jetson, to netboot or PXE boot a machine, or after building an image that needs to go on hardware. Also use when deciding whether a change can be switched, needs a full flash, or can be delivered over the network.
---

# Deploying to a Ghaf device

Three paths. The first two are the usual choice, and choosing wrong is expensive in opposite
directions: flashing when a switch would do wastes half an hour per iteration, while
switching when a flash was needed leaves a device that quietly disagrees with your source
tree. The third, netboot, delivers the same install as a flash without USB media — worth it
when reinstalling repeatedly or when the machine is not on your desk.

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
nix develop --command ghaf-rebuild ghaf-usb .#intel-laptop-debug boot
ssh ghaf-usb -- ssh ghaf-host sudo systemd-run --no-block systemctl reboot
```

**Default to `boot` plus a reboot rather than `switch`.** The reboot restarts every microVM,
so a guest-side change cannot sit unapplied while the host reports success — see the
microVM note below, which is the single most common way to conclude a fix didn't work when
it was never loaded. It also produces a real boot, and start-up ordering, readiness and
timing can only be judged on one. The cost is a couple of minutes of downtime on a rig that
is about to be rebooted by the next test anyway.

Issue the reboot detached (`systemd-run --no-block`): on a laptop the device address belongs
to net-vm, so the reboot kills the ssh connection carrying it, and a foreground `systemctl
reboot` can be killed with the session before it completes.

Use `switch` when you deliberately want no downtime, and then restart the affected microVMs
yourself:

```bash
nix develop --command ghaf-rebuild ghaf-usb .#intel-laptop-debug switch
nix develop --command ghaf-rebuild ghaf-usb .#intel-laptop-debug --force-local switch
nix develop --command ghaf-rebuild <netvm-ip> .#intel-laptop-debug switch   # also works
```

**Pass an ssh_config host alias, not a bare IP, whenever one exists.** ssh matches `Host`
blocks against the name *as written on the command line*, never the resolved address. So
unless you have a block that matches the address literally — a `Host 192.168.10.*` pattern,
say — an IP falls through to `Host *`, picks up no `IdentityFile`, and uses your default
keys. Where those are FIDO2/YubiKey-backed, the jump hop demands a touch per connection or
fails outright, while the second hop (`root@ghaf-host`, an alias) quietly works, which makes
the failure look like a device problem rather than a key-selection one. `ghaf-target`
describes where these aliases come from and why distinct names per device matter beyond
identity. Check what ssh will actually use before blaming the device:

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

## Path 3: netboot (tens of minutes, destructive, no USB)

The same install as Path 2, delivered over PXE. Use it when you would otherwise walk a USB
stick to the machine, or when reinstalling repeatedly: the boot artefacts are ~650 MB, carry
no disk image, and are target-independent, so only the image URL changes per target.

```bash
nix build .#intel-laptop-debug-netboot-installer -o result-netboot
nix build .#intel-laptop-debug -o result
nix develop --command ghaf-netboot -i <iface> -m <target-mac> \
  -n result-netboot -g result --dry-run          # always start here
sudo ghaf-netboot -i <iface> -m <target-mac> \
  -n result-netboot -g result --open-firewall --exit-after-serve
```

Preconditions, all of which fail quietly if unmet:

- **Secure Boot off** on the target — the chain is unsigned, exactly as the ISO is.
- **The target must have a network boot entry and firmware support for the NIC.** Not every
  USB-C adapter qualifies: the firmware needs its own driver for the chipset. A vendor dock
  usually works where a generic adapter emits no PXE request at all. Lenovo publishes the
  entry as `PXE BOOT`, an abstract `VenMsg(...)`, **not** as a `MAC(...)` device path — so do
  not test for `MAC(` when checking whether a machine can netboot.
- **Same layer-2 network.** PXE is broadcast; it does not cross a router.
- **`-i` is the build host's interface**, not the device's. `-m` is the target's PXE NIC —
  which on a docked laptop is the dock's MAC, not the internal one.

Flags that matter more than they look:

- `--open-firewall` — without it a filtering host drops PXE **before the server sees it**.
  The server logs nothing and looks healthy while the target times out.
- `--exit-after-serve` — stops the server once the image has transferred. **On by default with
  `--install-target`**: an unattended install reboots itself when done, so if network boot is
  ahead of the disk, a server left running catches that reboot and reinstalls in a loop.
  `--no-exit-after-serve` opts out and warns. Off for interactive runs, which need it up.
- `--force-interface` — needed whenever the interface facing the target also carries the
  default route, i.e. the normal case on a shared lab network.
- `--mac` is an allowlist and is mandatory. Anything not on it gets a 404, which PXE reads as
  "ignore me". On a shared network that is the only thing stopping an unrelated machine from
  booting your installer.

`--install-target /dev/nvme0n1` makes it unattended and destructive — see the safety section
above; the same "confirm the device" discipline applies, with nobody at the console. When the
write finishes the installer waits ten seconds and reboots itself into the new system; boot
with `ghaf.install_noreboot` to stay in the installer when you need to diagnose a bad install
rather than watch the evidence reboot away.

The installer is reachable over ssh as **`nixos@<ip>`** with the builder key, with passwordless
sudo. That is the honest completion check — `systemctl is-active ghaf-installer-tui.service`
and `/proc/cmdline` on the booted machine — rather than inferring success from server logs.

If nothing appears in the server log, work outwards in this order: is the firewall open, did
the firmware emit a PXE request at all (`tcpdump -i <iface> -e -vv 'udp port 67 or 69 or
4011'` — a real PXE request carries `PXEClient` and option 93), and does the MAC on the wire
match the allowlist.

### The decisive log line is `Sending ipxe boot script`

Everything before it can succeed while the boot still fails. Read the log by which of these
it looks like:

| What the log does | What it means |
| --- | --- |
| Reaches `Sending ipxe boot script` | iPXE got DHCP and is chaining. This is the good case. |
| A fresh `Got valid request ... (X64)` every ~35 s, forever | iPXE loaded but its own DHCP is failing — it retries ten times and reboots. |
| Serves the iPXE binary again every ~20 s | Chainload loop: the iPXE being served has no embedded `user-class pixiecore` script. |
| Nothing at all | Firewall, or the firmware never emitted a PXE request. See above. |

Ghaf serves its own `snponly.efi`, which uses the **firmware's** SNP driver and embeds the
`user-class pixiecore` handshake, so both loop cases should be history. If one reappears,
check `--dry-run`'s reported `ipxe` path is that binary rather than `pixiecore built-in`.
`--ipxe builtin` is the deliberate fallback for an adapter the firmware's SNP does not cover.

**Recovery from either loop can need physical access.** A separately powered USB-C dock keeps
its state across a laptop power cycle, so unplugging the dock is what actually clears it — do
not burn time on reboots that cannot work.

Every artefact can be served with a 200 while the target sits in an emergency shell. Assert on
the booted system, never on the transport.

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
