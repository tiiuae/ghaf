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

  Four ACPI patches, applied on x86_64 only, in
  `packages/pkgs-by-name/ghaf-qemu/patches/0001..0004`. They used to be a global qemu
  overlay; they now live in the standalone `ghaf-qemu` package. Drop them when the series
  is merged upstream and reaches the qemu in our nixpkgs.

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

- `0025-tegra-fbdev-use-core-allocated-fb-info.patch`

  In `.../passthrough/gpu-vm/patches/`, applied to `nvidia-oot-modules` from
  `.../passthrough/payload/guest-module.nix`. Kernel 6.12.103 backported
  `63c971af4036` and deleted `drm_fb_helper_alloc_info()`, so nvidia-oot's conftest
  ladder falls through to `drm_fb_helper_alloc_fbi()` — gone since v6.2 — and the tegra
  fbdev no longer compiles. Only Ghaf sees this, because the passthrough guests build
  the L4T out-of-tree modules against mainline `linuxPackages_6_12` rather than jetpack's
  own 5.15 kernel.

  Drop it when a `jetpack-nixos` bump brings an `nvidia-oot` that knows the new
  fb-helper contract.
