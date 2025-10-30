# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# pw-play does not work as intended in our environment, so use paplay instead
{ prev }:
(prev.cosmic-osd.overrideAttrs (oldAttrs: {
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace src/components/app.rs \
      --replace-fail 'pw-play' '${prev.pulseaudio}/bin/paplay'
  '';
}))
