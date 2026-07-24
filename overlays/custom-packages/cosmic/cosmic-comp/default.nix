# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-comp.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Add-security-context-indicator.patch
    ./0002-Disable-VRR-by-default.patch
    ./0003-cosmic-comp-egl-device.patch
  ];

  cargoPatches = (oldAttrs.cargoPatches or []) ++ [
    ./0004-Disable-EGL-enumeration.patch
  ];
})