# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# systemd service watchdogs are unsound in a guest.
#
# WatchdogSec is accounted against CLOCK_MONOTONIC. On bare metal that clock stops while the
# machine is suspended, so no service looks unresponsive across a sleep. A guest on kvm-clock
# does not stop: it advances 1:1 with wallclock while the host is suspended and the vCPUs are
# frozen. Measured on dell-ra13250 -- guest realtime and monotonic journal gaps both 312.4 s
# across a 312 s host s2idle (ratio 1.000), host monotonic gap 0.5 s. So every WatchdogSec
# service is already expired the moment the guest unfreezes, and systemd SIGABRTs it.
#
# Same boot, same VMs, two ~410 s suspends, only this flag changed:
#   watchdogs on  -> 15 kills + coredumps across net-vm, gui-vm, flatpak-vm
#   watchdogs off ->  0 kills; 17 "Watchdog disabled! Ignoring watchdog timeout" instead
# Affected units seen: logind, journald, journal-upload, oomd, networkd, udevd, timesyncd,
# resolved, in net-vm, audio-vm, gui-vm, admin-vm and flatpak-vm.
#
# power-manager's fakeSuspend does not fix this and cannot: it leaves the guest kernel
# running, so the clock keeps advancing and reaching sleep.target does not pause watchdog
# accounting. Verified with fakeSuspend running end to end in net-vm and audio-vm -- both
# were still killed on resume. This supersedes the per-unit
# `systemd-logind.serviceConfig.WatchdogSec = mkForce 0` in services/power.nix, which covered
# one unit in the gui-vm only.
#
# Kernel command line, not system.conf: systemd 261 has no ServiceWatchdogs= key there and
# logs `Unknown key 'ServiceWatchdogs' in section [Manager], ignoring` while leaving watchdogs
# on -- a silent no-op.
_: {
  boot.kernelParams = [ "systemd.service_watchdogs=false" ];
}
