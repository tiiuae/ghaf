# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes element-desktop
#
{ prev }:
prev.element-desktop.overrideAttrs (old: {
  # https://github.com/NixOS/nixpkgs/pull/160462
  installPhase = old.installPhase + ''
    wrapProgram $out/bin/element-desktop \
      --suffix PATH : ${prev.lib.makeBinPath [ prev.pkgs.xdg-utils ]}
  '';
})
