# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared system theming (stylix) module
#
# Applies common fonts, icons, and base16 color scheme to the host and all VMs.
# Note: Currently does not support COSMIC DE theming
#
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  _file = ./stylix.nix;

  imports = [ inputs.stylix.nixosModules.stylix ];

  options.ghaf.theming = {
    enable = mkEnableOption "shared system theming (stylix)";

    polarity = mkOption {
      type = types.enum [
        "light"
        "dark"
      ];
      default = "dark";
      description = "Light or dark color scheme polarity for shared theming";
    };

    base16Scheme = mkOption {
      type = types.path;
      default = ../desktop/graphics/cosmic/config/ghaf-themes/ghaf-dark-base16.yaml;
      description = "Path to the base16 scheme yaml used for shared theming";
    };

    iconTheme = {
      package = mkOption {
        type = types.str;
        default = "papirus-icon-theme";
        description = "Nixpkgs attribute name of the icon theme package";
      };
      light = mkOption {
        type = types.str;
        default = "Papirus-Light";
        description = "Icon theme name used in light mode";
      };
      dark = mkOption {
        type = types.str;
        default = "Papirus-Dark";
        description = "Icon theme name used in dark mode";
      };
    };

    fonts = {
      sansSerif = {
        package = mkOption {
          type = types.str;
          default = "inter";
          description = "Nixpkgs attribute name of the sans-serif font package";
        };
        name = mkOption {
          type = types.str;
          default = "Inter";
          description = "Sans-serif font family name";
        };
      };

      monospace = {
        package = mkOption {
          type = types.str;
          default = "jetbrains-mono";
          description = "Nixpkgs attribute name of the monospace font package";
        };
        name = mkOption {
          type = types.str;
          default = "JetBrains Mono";
          description = "Monospace font family name";
        };
      };

      emoji = {
        package = mkOption {
          type = types.str;
          default = "noto-fonts-color-emoji";
          description = "Nixpkgs attribute name of the emoji font package";
        };
        name = mkOption {
          type = types.str;
          default = "Noto Color Emoji";
          description = "Emoji font family name";
        };
      };
    };
  };

  config = lib.mkIf config.ghaf.theming.enable {
    stylix = {
      enable = true;

      # Currently unused
      targets.nixos-icons.enable = lib.mkDefault false;

      inherit (config.ghaf.theming) polarity base16Scheme;

      fonts = {
        serif = config.stylix.fonts.sansSerif;

        sansSerif = {
          package = pkgs.${config.ghaf.theming.fonts.sansSerif.package};
          inherit (config.ghaf.theming.fonts.sansSerif) name;
        };

        monospace = {
          package = pkgs.${config.ghaf.theming.fonts.monospace.package};
          inherit (config.ghaf.theming.fonts.monospace) name;
        };

        emoji = {
          package = pkgs.${config.ghaf.theming.fonts.emoji.package};
          inherit (config.ghaf.theming.fonts.emoji) name;
        };
      };

      icons = {
        enable = true;
        package = pkgs.${config.ghaf.theming.iconTheme.package};
        inherit (config.ghaf.theming.iconTheme) light dark;
      };

      targets.plymouth.logo = lib.mkIf config.ghaf.graphics.boot.logo.enable config.ghaf.graphics.boot.logo.image;
    };
  };
}
