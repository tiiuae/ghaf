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
{lib, ...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      gala-app = _final.callPackage ../user-apps/gala {};
      waypipe-ssh = _final.callPackage ../user-apps/waypipe-ssh {};
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
            // lib.optionalAttrs (lib.hasAttr "colord" (lib.functionArgs prev.weston.override)) {
              colord = null;
            }
            # NixOS Unstable has added these variables to control whether
            # pipewire, rdp or xwayland support should be present. They need to
            # be defined to false to avoid errors during the build.
            # TODO: When moving to NixOS 23.11, these optionalAttrs can just be
            #       removed, and the attributes can be combined to single
            #       attribute set.
            // lib.optionalAttrs (lib.hasAttr "pipewireSupport" (lib.functionArgs prev.weston.override)) {
              pipewireSupport = false;
            }
            // lib.optionalAttrs (lib.hasAttr "rdpSupport" (lib.functionArgs prev.weston.override)) {
              rdpSupport = false;
            }
            // lib.optionalAttrs (lib.hasAttr "xwaylandSupport" (lib.functionArgs prev.weston.override)) {
              xwaylandSupport = false;
            }
          )
        )
        # and then this overridden package's attributes are overridden
        .overrideAttrs (prevAttrs:
          lib.optionalAttrs (lib.hasAttr "colord" (lib.functionArgs prev.weston.override)) {
            # Only override mesonFlags if colord argument is accepted
            mesonFlags = prevAttrs.mesonFlags ++ ["-Ddeprecated-color-management-colord=false"];
          });
      systemd = prev.systemd.overrideAttrs (prevAttrs: {
        patches = prevAttrs.patches ++ [./systemd-timesyncd-disable-nscd.patch];
        postPatch =
          prevAttrs.postPatch
          + ''
            substituteInPlace units/systemd-timesyncd.service.in \
              --replace \
              "Environment=SYSTEMD_NSS_RESOLVE_VALIDATE=0" \
              "${lib.concatStringsSep "\n" [
              "Environment=LD_LIBRARY_PATH=$out/lib"
              "Environment=SYSTEMD_NSS_RESOLVE_VALIDATE=0"
            ]}"
          '';
      });
    })
  ];
}
