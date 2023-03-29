# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for custom packages - new packages, like Gala, or
# fixed/adjusted packages from nixpkgs
# The overlay might be used as an example and starting point for
# any other overlays.
#
# !!!!!!! HINT !!!!!!!!
# Use final/prev pair in your overlays instead of other variations
# since it looks more logical:
# previous (unmodified) package vs final (finalazed, adjusted) package.
#
# !!!!!!! HINT !!!!!!!!
# Use deps[X][Y] variations instead of juggling dependencies between
# nativeBuildInputs and buildInputs where possible.
# It makes things clear and robust.
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
      pipewire = prev.pipewire.overrideAttrs (prevAttrs: {
        nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [pkgs.glib];
        depsBuildBuild = [pkgs.gettext];
      });
      # TODO: Remove this override if/when the fix is upstreamed.
      # Disabling colord dependency for weston. Colord has argyllcms as
      # a dependency, and this package is not cross-compilable.
      # Nowadays, colord even marked as deprecated option for weston.
      weston =
        # First, weston package is overridden (passing colord = null)
        (prev.weston.override {
          colord = null;
        })
        # and then this overridden package's attributes are overridden
        .overrideAttrs (prevAttrs: {
          mesonFlags = prevAttrs.mesonFlags ++ ["-Ddeprecated-color-management-colord=false"];
          depsBuildBuild = [pkgs.pkg-config];
        });
      # TODO: Remove this override if/when the fix is upstreamed.
      # Removing wayland dependency from runtime dependencies and making it
      # native build time dependency
      freerdp = prev.freerdp.overrideAttrs (prevAttrs: {
        buildInputs = lib.remove pkgs.wayland prevAttrs.buildInputs;
        depsBuildBuild = [pkgs.wayland];
      });
    })
  ];
}
