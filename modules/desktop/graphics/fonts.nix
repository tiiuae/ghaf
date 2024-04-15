# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (config.ghaf.graphics) weston labwc;
in {
  config = lib.mkIf (weston.enable || labwc.enable) {
    fonts.packages = with pkgs; [
      fira-code-nerdfont
      hack-font
    ];
  };
}
