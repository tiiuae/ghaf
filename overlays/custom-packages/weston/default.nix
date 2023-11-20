# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes weston - see comments for details
#
(final: prev: {
  # TODO: Remove this override if/when the fix is upstreamed.
  # Disabling colord dependency for weston. Colord has argyllcms as
  # a dependency, and this package is not cross-compilable.
  # Nowadays, colord even marked as deprecated option for weston.
  weston =
    # First, weston package is overridden (passing colord = null)
    (
      prev.weston.override (
        {
          pipewire = null;
          freerdp = null;
          xwayland = null;
        }
        # Only override colord if the package takes such argument. In NixOS
        # 23.05, the Weston package still uses colord as a dependency, but it
        # has been removed in NixOS Unstable. Otherwise there will be an
        # error about unexpected argument.
        // final.lib.optionalAttrs (final.lib.hasAttr "colord" (final.lib.functionArgs prev.weston.override)) {
          colord = null;
        }
        # NixOS Unstable has added these variables to control whether
        # pipewire, rdp or xwayland support should be present. They need to
        # be defined to false to avoid errors during the build.
        # TODO: When moving to NixOS 23.11, these optionalAttrs can just be
        #       removed, and the attributes can be combined to single
        #       attribute set.
        // final.lib.optionalAttrs (final.lib.hasAttr "pipewireSupport" (final.lib.functionArgs prev.weston.override)) {
          pipewireSupport = false;
        }
        // final.lib.optionalAttrs (final.lib.hasAttr "rdpSupport" (final.lib.functionArgs prev.weston.override)) {
          rdpSupport = false;
        }
        // final.lib.optionalAttrs (final.lib.hasAttr "xwaylandSupport" (final.lib.functionArgs prev.weston.override)) {
          xwaylandSupport = false;
        }
        // final.lib.optionalAttrs (final.lib.hasAttr "vncSupport" (final.lib.functionArgs prev.weston.override)) {
          vncSupport = false;
        }
      )
    )
    # and then this overridden package's attributes are overridden
    .overrideAttrs (
      prevAttrs:
        final.lib.optionalAttrs (final.lib.hasAttr "colord" (final.lib.functionArgs prev.weston.override)) {
          # Only override mesonFlags if colord argument is accepted
          mesonFlags = prevAttrs.mesonFlags ++ ["-Ddeprecated-color-management-colord=false"];
        }
        // {
          patches = [./weston-backport-workspaces.patch];
        }
    );
})
