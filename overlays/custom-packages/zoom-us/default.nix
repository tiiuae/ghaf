# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev, ... }:
# Disable zoom launcher
prev.zoom-us.overrideAttrs (_prevAttrs: {
  
  postFixup = _prevAttrs.postFixup + ''
          substituteInPlace $out/bin/zoom \
          --prefix LD_LIBRARY_PATH ":" "$out/opt/zoom/Qt/lib/"
          --replace opt/zoom/ZoomLauncher opt/zoom/zoom
        '';
})
