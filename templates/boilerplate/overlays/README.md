<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors

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

The status of the integration in nixpkgs can be tracked using the [Pull Request Tracker](https://nixpk.gs/pr-tracker.html)

## From Overlays


## carried in tiiuae/nixpkgs/
