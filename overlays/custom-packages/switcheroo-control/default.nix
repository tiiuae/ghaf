# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
# TODO: drop after nixpkgs declares native GLib; tracked in https://github.com/tiiuae/ghaf/pull/2373.
if prev.stdenv.buildPlatform.system == prev.stdenv.hostPlatform.system then
  prev.switcheroo-control
else
  prev.switcheroo-control.overrideAttrs (old: {
    # Meson needs a native glib-compile-resources when generating GPU data.
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.buildPackages.glib ];
  })
