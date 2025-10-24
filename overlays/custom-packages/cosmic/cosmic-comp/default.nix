# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-comp.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Add-security-context-indicator.patch
    ./0001-Disable-VRR-by-default.patch
  ];
})
