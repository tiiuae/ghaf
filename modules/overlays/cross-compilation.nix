# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.overlays = [
    (final: prev: {
      # TODO: Remove this override if/when the fix is upstreamed.
      # Adding missing dependencies for pipewire
      #
      # Overriding pipewire causes massive rebuild of chromium, so putting it
      # into this separate overlay, so all targets don't need to rebuild
      # chromium.
      #
      # This can be removed when we move to NixOS 23.05
      #
      pipewire = prev.pipewire.overrideAttrs (prevAttrs: {
        nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [pkgs.glib];
        depsBuildBuild = [pkgs.gettext];
      });
    })
  ];
}
