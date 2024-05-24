# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{prev, ...}:
# Waypipe with vsock and window borders
prev.waypipe.overrideAttrs (_prevAttrs: {
  patches = [./waypipe-window-borders.patch];
})
