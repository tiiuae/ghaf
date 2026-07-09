# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Add missing plugins and path
# TODO: Remove after https://github.com/NixOS/nixpkgs/pull/534694 is merged and available
{ prev }:
(prev.cosmic-player.overrideAttrs (oldAttrs: {
  dontWrapLibcosmicApp = true;

  postFixup = oldAttrs.postFixup or "" + ''
    wrapLibcosmicApp "$out/bin/cosmic-player" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0"
  '';
}))
