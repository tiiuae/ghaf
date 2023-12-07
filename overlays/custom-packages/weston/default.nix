# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes weston - see comments for details
#
(final: prev: {
  weston =
    # First, weston package is overridden
    (
      prev.weston.override {
        freerdp = null;
        pipewire = null;
        pipewireSupport = false;
        rdpSupport = false;
        vncSupport = false;
        xwayland = null;
        xwaylandSupport = false;
      }
    )
    # and then this overridden package's attributes are overridden
    .overrideAttrs (
      _prevAttrs:
      # TODO: Add patch for 13.0 which is coming in NixOS 24.05
        final.lib.optionalAttrs ((final.lib.versions.majorMinor prev.weston.version) == "12.0") {
          patches = [./weston-backport-workspaces.patch];
        }
    );
})
