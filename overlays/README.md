<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Custom packages overlay

This overlay is for custom packages - new packages, like Gala, or
fixed/adjusted packages from nixpkgs. The overlay might be used as
an example and starting point for any other overlays.

# Cross-compilation overlay

This overlay is for fixes regarding cross-compilation. It is maintained as a
separate overlay, because some of the changes might trigger heavy rebuilds of
packages in nixpkgs. It can then be separately added to cross-compilation
builds.

## General Requirements

Use final/prev pair in your overlays instead of other variations
since it looks more logical:
previous (unmodified) package vs final (finalazed, adjusted) package.

Use deps[X][Y] variations instead of juggling dependencies between
nativeBuildInputs and buildInputs where possible.
It makes things clear and robust.

# Upstream PR and commit tracking

Some patches are carried as overlays and others are patches that are cherry-picked
from staging and main into a tiiuae maintained version of nixpkgs
[tiiuae/nixpkgs/...](https://github.com/tiiuae/nixpkgs/)

The status of the integration in nixpkgs can be tracked using the [Pull Request Tracker](https://nixpk.gs/pr-tracker.html)

## Carried patches in ghaf packages

- [qemu: Battery, AC adapter, lid](https://github.com/blochl/qemu/pull/3)

  Four ACPI patches, applied on x86_64 only, in the standalone `ghaf-x86-qemu`
  package from ghafpkgs. Drop them when the series is merged upstream and
  reaches the qemu in our nixpkgs.

## Backports carried in overlays



## Inputs pinned to an unmerged PR

A rev pin freezes *every* change in that input, not just the one being carried, so it must be
repointed at the branch head as soon as the PR merges.

## carried in tiiuae/nixpkgs/...

None at the moment. Anything landed here is in nixpkgs staging, so carry it for some time
until it reaches unstable.

## Carried workarounds in ghaf modules

Not every carried change is an overlay. These live in ghaf's own modules and CI, and
only exist until an upstream fix lands, so they should be reverted rather than maintained.

- `fix(microvm): wait for a stopping guest instead of killing it immediately`

  Appends a waiter to `microvm@`'s `ExecStop` in `modules/microvm/host/microvm-host.nix`,
  because microvm.nix's own `ExecStop` returns immediately under systemd and the guest is
  killed before it can shut down.

  Revert that commit when
  [microvm.nix#578](https://github.com/microvm-nix/microvm.nix/pull/578) is merged and the
  `microvm` input is bumped past it — find it with
  `git log --grep 'wait for a stopping guest'`.

- `modules/common/systemd/tmpfiles-portables.nix`

  NixOS's `nixos/modules/system/boot/systemd/tmpfiles.nix` links
  `${systemd}/example/tmpfiles.d/portables.conf` unconditionally, but systemd installs that
  file only when portabled is built. Every ghaf systemd comes from `systemdMinimal`
  (`modules/common/systemd/base.nix`), which leaves portabled off, so
  `/etc/tmpfiles.d/portables.conf` dangles and each `systemd-tmpfiles` run logs
  `Failed to chase '/etc/tmpfiles.d/portables.conf'` — three times per boot, on the host and
  on every VM.

  Drop it when [NixOS#553061](https://github.com/NixOS/nixpkgs/pull/553061) reaches our pin.
  The upstream fix omits the link entirely, which is tidier than shipping an empty conf; test
  for it directly rather than by date:

  ```bash
  git -C <nixpkgs> grep -q withPortabled <our-pin> -- nixos/modules/system/boot/systemd/tmpfiles.nix
  ```

- `0025-tegra-fbdev-use-core-allocated-fb-info.patch`

  Carried by jetpack-nixos and applied to `nvidia-oot-modules` from
  the GPU partitioning examples' Orin guest module. Kernel 6.12.103 backported
  `63c971af4036` and deleted `drm_fb_helper_alloc_info()`, so nvidia-oot's conftest
  ladder falls through to `drm_fb_helper_alloc_fbi()` — gone since v6.2 — and the tegra
  fbdev no longer compiles. Only Ghaf sees this, because the passthrough guests build
  the L4T out-of-tree modules against mainline `linuxPackages_6_12` rather than jetpack's
  own 5.15 kernel.

  Drop it from jetpack-nixos when its `nvidia-oot` knows the new fb-helper
  contract.
