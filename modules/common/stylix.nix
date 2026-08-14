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
let
  inherit (lib) mkEnableOption mkOption types;

  # Upstream stylix themes GTK and Qt only via Home Manager. We have no
  # per-user HM sessions, so we write the same config under /etc/xdg instead,
  # which both read as the system-wide equivalent of $XDG_CONFIG_HOME.
  # https://github.com/nix-community/stylix/issues/484

  iconThemeName =
    if config.ghaf.theming.polarity == "dark" then
      config.ghaf.theming.iconTheme.dark
    else
      config.ghaf.theming.iconTheme.light;

  fontSize = toString config.stylix.fonts.sizes.applications;

  gtkThemePackage = pkgs.adw-gtk3;
  gtkThemeName = "adw-gtk3";

  gtkCss = config.lib.stylix.colors {
    template = "${inputs.stylix}/modules/gtk/gtk.css.mustache";
    extension = ".css";
  };

  gtkSettingsIni = pkgs.writeText "gtk-settings.ini" ''
    [Settings]
    gtk-application-prefer-dark-theme=${
      if config.ghaf.theming.polarity == "dark" then "true" else "false"
    }
    gtk-theme-name=${gtkThemeName}
    gtk-icon-theme-name=${iconThemeName}
    gtk-font-name=${config.ghaf.theming.fonts.sansSerif.name} ${fontSize}
  '';

  kvantumThemePackage =
    let
      kvconfig = config.lib.stylix.colors {
        template = "${inputs.stylix}/modules/qt/kvconfig.mustache";
        extension = ".kvconfig";
      };
      svg = config.lib.stylix.colors {
        template = "${inputs.stylix}/modules/qt/kvantum.svg.mustache";
        extension = ".svg";
      };
    in
    pkgs.runCommandLocal "base16-kvantum" { } ''
      directory="$out/share/Kvantum/Base16Kvantum"
      mkdir --parents "$directory"
      cp ${kvconfig} "$directory/Base16Kvantum.kvconfig"
      cp ${svg} "$directory/Base16Kvantum.svg"
    '';

  kvantumConfig = pkgs.writeText "kvantum.kvconfig" ''
    [General]
    theme=Base16Kvantum
  '';

  qtctSettingsIni = pkgs.writeText "qtct-settings.ini" ''
    [Appearance]
    custom_palette=true
    icon_theme=${iconThemeName}
    standard_dialogs=default
    style=kvantum

    [Fonts]
    fixed="${config.ghaf.theming.fonts.monospace.name},${fontSize}"
    general="${config.ghaf.theming.fonts.sansSerif.name},${fontSize}"
  '';
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

  config = lib.mkIf config.ghaf.theming.enable (
    lib.mkMerge [
      {
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

          targets.plymouth = {
            logo = lib.mkIf config.ghaf.graphics.boot.logo.enable config.ghaf.graphics.boot.logo.image;
            logoAnimated = false;
          };
        };
      }

      (lib.mkIf config.stylix.targets.gtk.enable {
        environment.etc = {
          "xdg/gtk-3.0/settings.ini".source = gtkSettingsIni;
          "xdg/gtk-4.0/settings.ini".source = gtkSettingsIni;
          "xdg/gtk-3.0/gtk.css".source = gtkCss;
          "xdg/gtk-4.0/gtk.css".source = gtkCss;
        };

        environment.systemPackages = [ gtkThemePackage ];

        # Some GTK apps read theme settings via gsettings/dconf instead of settings.ini.
        programs.dconf.enable = lib.mkForce true;
      })

      (lib.mkIf config.stylix.targets.qt.enable {
        environment.etc = {
          "xdg/qt5ct/qt5ct.conf".source = qtctSettingsIni;
          "xdg/qt6ct/qt6ct.conf".source = qtctSettingsIni;
          "xdg/Kvantum/kvantum.kvconfig".source = kvantumConfig;
        };

        environment.systemPackages = [ kvantumThemePackage ];

        qt = {
          enable = lib.mkForce true;
          platformTheme = lib.mkForce "qt5ct";
          style = lib.mkForce "kvantum";
        };
      })
    ]
  );
}
