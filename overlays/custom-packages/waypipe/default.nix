# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev, ... }:
# Waypipe with vsock and window borders
prev.waypipe.overrideAttrs (_prevAttrs: {
  # Upstream pull request: https://gitlab.freedesktop.org/mstoeckl/waypipe/-/merge_requests/21
  patches = [ ./waypipe-window-borders.patch ];
})
