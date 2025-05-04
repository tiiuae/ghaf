# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-comp.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [ ./0001-Add-security-context-indicator.patch ];
})
