# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
in {
  config = lib.mkIf cfg.enable {
    fonts.fonts = with pkgs; [
      fira-code
      hack-font
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
    ];
  };
}
