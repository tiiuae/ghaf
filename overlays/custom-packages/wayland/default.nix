# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Patched libwayland-client for the COSMIC apps the xdg handlers launch, which
# segfault when proxies are destroyed after the display's object map is released.
# Scoped to those apps, as patching the global wayland rebuilds every graphics
# package.
{ prev }:
let
  wayland = prev.wayland.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./0001-wayland-map-poison-guard.patch
    ];
  });
in
# libcosmic apps link libwayland-client through libcosmicAppHook's cargo link flags.
pkg: pkg.override { libcosmicAppHook = prev.libcosmicAppHook.override { inherit wayland; }; }
