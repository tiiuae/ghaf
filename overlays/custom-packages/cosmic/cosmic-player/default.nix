# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Reduce closure size by disabling tesseract mupdf feature
# Saves approx 900 MB
{ prev }:
prev.cosmic-player.overrideAttrs (oldAttrs: {
  postFixup = (oldAttrs.postFixup or "") + ''
    wrapProgram $out/bin/cosmic-player \
      --set RUST_LOG "cosmic_player=trace" \
      --set WAYLAND_DEBUG "1" \
      --set WGPU_LOG_LEVEL "debug"
  '';
})
