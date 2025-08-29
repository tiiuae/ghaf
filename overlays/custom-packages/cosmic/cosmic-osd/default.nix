# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.cosmic-osd.overrideAttrs (oldAttrs: rec {
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace src/components/app.rs \
      --replace-fail 'pw-play' '${prev.pulseaudio}/bin/paplay'
  '';
}))
