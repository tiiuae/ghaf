# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes weston - see comments for details
#
(_final: prev: {
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
      _prevAttrs: {
        patches = [./weston-backport-workspaces.patch];
      }
    );
})
