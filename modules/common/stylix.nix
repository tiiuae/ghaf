# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared system theming (stylix) module
#
# Applies common fonts, icons, and base16 color scheme to the host and all VMs.
#
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
{
  _file = ./stylix.nix;

  imports = [ inputs.stylix.nixosModules.stylix ];

  config = lib.mkIf config.ghaf.global-config.theming.enable {
    stylix = {
      enable = true;

      base16Scheme = config.ghaf.global-config.theming.base16Scheme;

      fonts = {
        serif = config.stylix.fonts.sansSerif;

        sansSerif = {
          package = pkgs.inter;
          name = "Inter";
        };

        monospace = {
          package = pkgs.jetbrains-mono;
          name = "JetBrains Mono";
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };

      icons = {
        enable = true;
        package = pkgs.papirus-icon-theme;
        light = "Papirus-Light";
        dark = "Papirus-Dark";
      };
    };
  };
}
