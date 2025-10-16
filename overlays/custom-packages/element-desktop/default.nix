# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes element-desktop
#
{ prev }:

prev.element-desktop.overrideAttrs (old: {
  patches = [ ./element-main.patch ];
  # https://github.com/NixOS/nixpkgs/pull/160462
  installPhase = old.installPhase + ''
    wrapProgram $out/bin/element-desktop \
      --suffix PATH : ${prev.lib.makeBinPath [ prev.xdg-utils ]} \
      --set LIBGL_ALWAYS_SOFTWARE 1 \
      --set ELECTRON_DISABLE_GPU true \
      --set ELECTRON_ENABLE_LOGGING 1
  '';
})
