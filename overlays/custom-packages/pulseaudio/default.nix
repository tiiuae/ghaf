# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev, ... }:
prev.pulseaudio.overrideAttrs (_prevAttrs: {
  # This patch enables the live switching of pulse tunnels to different sinks
  patches = _prevAttrs.patches ++ [ ./pulseaudio-remove-dont-move.patch ];
})
