# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev, ... }:
# Disable zoom launcher
prev.zoom-us.overrideAttrs (_prevAttrs: {
  
  postFixup = _prevAttrs.postFixup + ''
          substituteInPlace $out/opt/zoom/ZoomWebviewHost \
          --replace-fail "exec" 'PATH=$PATH:/run/current-system/sw/bin/${"\n"}export LD_LIBRARY_PATH${"\n"}LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${prev.zoom-us.out}/opt/zoom/Qt/lib/:${prev.zoom-us.out}/opt/zoom/cef/${"\n"}export LD_LIBRARY_PATH${"\n"}exec' \
          --replace-fail 'ZoomWebviewHost-wrapped"' 'ZoomWebviewHost-wrapped" "--enable-features=UseOzonePlatform" "--ozone-platform=wayland"' \
          --replace-fail '"$0"' '"$0" "/run/current-system/sw/bin/run-waypipe"'
          
          substituteInPlace $out/bin/zoom \
          --replace-fail "exec" 'PATH=$PATH:/run/current-system/sw/bin/ LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${prev.zoom-us.out}/opt/zoom/Qt/lib/${"\n"}export LD_LIBRARY_PATH${"\n"}exec' \
          --replace-fail opt/zoom/ZoomLauncher opt/zoom/zoom
        '';
        
})
