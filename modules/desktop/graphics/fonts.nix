# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.ghaf.graphics) labwc cosmic;
in
{
  config = lib.mkIf (labwc.enable || cosmic.enable) {
    fonts.packages =
      [
        pkgs.inter
      ]
      ++ (
        if labwc.enable then
          [
            pkgs.nerd-fonts.fira-code
            pkgs.hack-font
          ]
        else
          [ ]
      );
  };
}
