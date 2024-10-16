# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev, ... }:
# Waypipe with vsock and window borders
prev.waypipe.overrideAttrs (_prevAttrs: {
  # Upstream pull request: https://gitlab.freedesktop.org/mstoeckl/waypipe/-/merge_requests/21
  patches = [
    ./waypipe-fix-reading-data-from-pipes.patch
    ./waypipe-window-borders.patch
    ./waypipe-security-context.patch
  ];
  nativeBuildInputs = _prevAttrs.nativeBuildInputs ++ [ prev.pkgs.wayland-scanner ];
  buildInputs = _prevAttrs.buildInputs ++ [ prev.pkgs.wayland ];
})
