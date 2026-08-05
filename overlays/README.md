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

## From Overlays

[qemu: Battery, lid, power](https://github.com/blochl/qemu/pull/3)
[gjs - cross](https://github.com/NixOS/nixpkgs/pull/461666)
[oculante: Generated Nix Path Changed](https://github.com/NixOS/nixpkgs/pull/502921)
[python3Packages.pandas-stubs: pin pytest to 9.0](https://github.com/NixOS/nixpkgs/pull/545267)

## carried in tiiuae/nixpkgs/...

The following are in staging at the moment, so carry for some time until they reach unstable.

## Carried workarounds in ghaf modules

Not every carried change is an overlay. These live in ghaf's own modules and only
exist until an upstream fix lands, so they should be reverted rather than maintained.

- `fix(microvm): wait for a stopping guest instead of killing it immediately`

  Appends a waiter to `microvm@`'s `ExecStop` in `modules/microvm/host/microvm-host.nix`,
  because microvm.nix's own `ExecStop` returns immediately under systemd and the guest is
  killed before it can shut down.

  Revert that commit when
  [microvm.nix#578](https://github.com/microvm-nix/microvm.nix/pull/578) is merged and the
  `microvm` input is bumped past it — find it with
  `git log --grep 'wait for a stopping guest'`.
