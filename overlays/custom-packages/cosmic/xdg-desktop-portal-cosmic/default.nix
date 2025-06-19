# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Cross-compilation fix: glib-sys fails without glib
{ prev }:
prev.xdg-desktop-portal-cosmic.overrideAttrs (oldAttrs: {
  buildInputs = oldAttrs.buildInputs ++ [ prev.glib ];
})
