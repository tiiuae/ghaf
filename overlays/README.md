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

  Four ACPI patches, applied on x86_64 only, in the standalone `ghaf-qemu`
  package from ghafpkgs. Drop them when the series is merged upstream and
  reaches the qemu in our nixpkgs.

## Backports carried in overlays

- [gobject-introspection: don't abort builds when g-ir-scanner is absent](https://github.com/NixOS/nixpkgs/pull/557920)

  `overlays/cross-compilation/default.nix` adds `gobject-introspection` to
  `dbus-python`'s `nativeBuildInputs`.

   [nixpkgs#540549](https://github.com/NixOS/nixpkgs/pull/540549)
  (`dbus-python: Re-enable tests`) is what exposed it, by adding `pygobject3` to
  `checkInputs`. It reached our pin in the 2026-08-25 bump and broke every Jetson
  `-from-x86_64` target.

  Drop the overlay entry once #557920 lands. Test for the fix itself rather than
  by date:

  ```bash
  grep -q 'type -p g-ir-scanner || true' \
    <our-pin>/pkgs/development/libraries/gobject-introspection/wrapper.nix
  ```

## Inputs pinned to an unmerged PR

A rev pin freezes *every* change in that input, not just the one being carried, so it must be
repointed at the branch head as soon as the PR merges.

## carried in tiiuae/nixpkgs/...

None at the moment. Anything landed here is in nixpkgs staging, so carry it for some time
until it reaches unstable.

## Carried workarounds in ghaf modules

Not every carried change is an overlay. These live in ghaf's own modules and CI, and
only exist until an upstream fix lands, so they should be reverted rather than maintained.

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
