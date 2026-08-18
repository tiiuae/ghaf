# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
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
  cfg = config.ghaf.theming;

  # Upstream stylix themes GTK and Qt only via Home Manager. We have no
  # per-user HM sessions, so we write the same config under /etc/xdg instead,
  # which both read as the system-wide equivalent of $XDG_CONFIG_HOME.
  # https://github.com/nix-community/stylix/issues/484

  iconThemeName = if cfg.polarity == "dark" then cfg.iconTheme.dark else cfg.iconTheme.light;

  fontSize = toString config.stylix.fonts.sizes.applications;

  gtkThemePackage = pkgs.adw-gtk3;
  gtkThemeName = "adw-gtk3";

  gtkCss = config.lib.stylix.colors {
    # Must be the mustache source text, not a path string - base16.nix's
    # mkTheme treats any string as literal template content.
    template = builtins.readFile "${inputs.stylix}/modules/gtk/gtk.css.mustache";
    extension = ".css";
  };

  gtkSettingsIni = pkgs.writeText "gtk-settings.ini" ''
    [Settings]
    gtk-application-prefer-dark-theme=${if cfg.polarity == "dark" then "true" else "false"}
    gtk-theme-name=${gtkThemeName}
    gtk-icon-theme-name=${iconThemeName}
    gtk-font-name=${cfg.fonts.sansSerif.name} ${fontSize}
  '';

  kvantumThemePackage =
    let
      kvconfig = config.lib.stylix.colors {
        template = builtins.readFile "${inputs.stylix}/modules/qt/kvconfig.mustache";
        extension = ".kvconfig";
      };
      svg = config.lib.stylix.colors {
        template = builtins.readFile "${inputs.stylix}/modules/qt/kvantum.svg.mustache";
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
    fixed="${cfg.fonts.monospace.name},${fontSize}"
    general="${cfg.fonts.sansSerif.name},${fontSize}"
  '';

  plymouthSpinnerThemeDir = "${pkgs.plymouth}/share/plymouth/themes/spinner";

  # Number of "throbber-NNNN.png" frames shipped by pkgs.plymouth's own
  # "spinner" theme, reused under our logo.
  plymouthSpinnerFrameCount = 30;

  plymouthThemeScript = import ./plymouth-theme-script.nix {
    inherit lib;
    cfg = cfg.plymouth;
    colors = config.lib.stylix.colors;
    spinnerFrameCount = plymouthSpinnerFrameCount;
  };

  plymouthTheme = pkgs.runCommand "ghaf-plymouth" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    themeDir="$out/share/plymouth/themes/ghaf"
    mkdir -p "$themeDir"

    if [ -n "${cfg.plymouth.logo}" ]; then
      # Resize the image to a height of 200px, keeping aspect ratio
      magick convert "${cfg.plymouth.logo}" \
        -background transparent -resize x200 \
        $themeDir/logo.png
    fi
    cp ${plymouthSpinnerThemeDir}/throbber-*.png "$themeDir/"
    cp ${plymouthThemeScript} "$themeDir/ghaf.script"

    echo "
    [Plymouth Theme]
    Name=Ghaf
    ModuleName=script

    [script]
    ImageDir=$themeDir
    ScriptFile=$themeDir/ghaf.script
    " > "$themeDir/ghaf.plymouth"
  '';
in
{
  _file = ./default.nix;

  imports = [ inputs.stylix.nixosModules.stylix ];

  options.ghaf.theming = {
    enable = lib.mkEnableOption "shared system theming (stylix)";

    polarity = lib.mkOption {
      type = lib.types.enum [
        "light"
        "dark"
      ];
      default = "dark";
      description = "Light or dark color scheme polarity for shared theming";
    };

    base16Scheme = lib.mkOption {
      type = lib.types.path;
      default = ./ghaf-dark-base16.yaml;
      example = ./ghaf-light-base16.yaml;
      description = "Path to the base16 scheme yaml used for shared theming";
    };

    iconTheme = {
      package = lib.mkOption {
        type = lib.types.str;
        default = "papirus-icon-theme";
        description = "Nixpkgs attribute name of the icon theme package";
      };
      light = lib.mkOption {
        type = lib.types.str;
        default = "Papirus-Light";
        description = "Icon theme name used in light mode";
      };
      dark = lib.mkOption {
        type = lib.types.str;
        default = "Papirus-Dark";
        description = "Icon theme name used in dark mode";
      };
    };

    fonts = {
      sansSerif = {
        package = lib.mkOption {
          type = lib.types.str;
          default = "inter";
          description = "Nixpkgs attribute name of the sans-serif font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Inter";
          description = "Sans-serif font family name";
        };
      };

      monospace = {
        package = lib.mkOption {
          type = lib.types.str;
          default = "jetbrains-mono";
          description = "Nixpkgs attribute name of the monospace font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "JetBrains Mono";
          description = "Monospace font family name";
        };
      };

      emoji = {
        package = lib.mkOption {
          type = lib.types.str;
          default = "noto-fonts-color-emoji";
          description = "Nixpkgs attribute name of the emoji font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Noto Color Emoji";
          description = "Emoji font family name";
        };
      };
    };

    plymouth = {
      enable = lib.mkEnableOption "Plymouth (boot splash) global theming";

      logo = lib.mkOption {
        description = "Logo to be used on the boot screen.";
        type = with lib.types; either path package;
        defaultText = lib.literalMD "Ghaf logo";
        default = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.png";
      };

      spinnerAnimated = lib.mkOption {
        description = "Whether to animate Plymouth's spinner shown under the logo.";
        type = lib.types.bool;
        default = true;
      };

      bootLabel = lib.mkOption {
        description = ''
          Status text shown under the logo while booting. Empty shows nothing.

          Useful to distinguish separate boot screens shown in sequence, e.g.
          the host and gui-vm each showing their own Plymouth splash.
        '';
        type = lib.types.str;
        default = "";
        example = "Starting desktop...";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        stylix = {
          enable = true;

          # Currently unused
          targets.nixos-icons.enable = lib.mkDefault false;

          inherit (cfg) polarity base16Scheme;

          fonts = {
            serif = config.stylix.fonts.sansSerif;

            sansSerif = {
              package = pkgs.${cfg.fonts.sansSerif.package};
              inherit (cfg.fonts.sansSerif) name;
            };

            monospace = {
              package = pkgs.${cfg.fonts.monospace.package};
              inherit (cfg.fonts.monospace) name;
            };

            emoji = {
              package = pkgs.${cfg.fonts.emoji.package};
              inherit (cfg.fonts.emoji) name;
            };
          };

          icons = {
            enable = true;
            package = pkgs.${cfg.iconTheme.package};
            inherit (cfg.iconTheme) light dark;
          };

          # We build our own Plymouth theme below instead, so that we can show
          # Plymouth's own spinner under the logo rather than spinning the logo.
          targets.plymouth.enable = false;
        };

        environment.systemPackages = lib.mkAfter (
          lib.rmDesktopEntries [
            pkgs.libsForQt5.qt5ct
            pkgs.qt6Packages.qt6ct
          ]
        );
      }

      # Flatpak apps run sandboxed and don't see our system-wide GTK/Qt
      # config, so this rebuilds it as a self-contained store path shared
      # in via a Flatpak filesystem + XDG_DATA_DIRS/XDG_CONFIG_DIRS override.
      (lib.mkIf config.services.flatpak.enable (
        let
          flattenedGtkTheme = pkgs.stdenvNoCC.mkDerivation {
            name = "flattenedGtkTheme";
            src = "${gtkThemePackage}/share/themes/${gtkThemeName}";

            installPhase = ''
              themeDir="$out/share/themes/${gtkThemeName}"
              mkdir -p "$themeDir"
              cp --recursive . "$themeDir"
              cat ${gtkCss} | tee --append "$themeDir"/gtk-{3,4}.0/gtk.css

              mkdir -p "$out"/config/gtk-{3,4}.0
              cat ${gtkSettingsIni} | tee "$out"/config/gtk-{3,4}.0/settings.ini > /dev/null
            '';
          };

          flatpakGlobalOverride = pkgs.writeText "flatpak-global-override" ''
            [Context]
            filesystems=${flattenedGtkTheme}:ro

            # Flatpak always overrides XDG_DATA_DIRS/XDG_CONFIG_DIRS, so
            # these restate Flatpak's own defaults plus our theme dir.
            [Environment]
            XDG_DATA_DIRS=${flattenedGtkTheme}/share:/app/share:/usr/share:/usr/share/runtime/share:/run/host/user-share:/run/host/share
            XDG_CONFIG_DIRS=${flattenedGtkTheme}/config:/app/etc/xdg:/etc/xdg
          '';
        in
        {
          systemd.tmpfiles.rules = [
            "L+ /var/lib/flatpak/overrides/global - - - - ${flatpakGlobalOverride}"
          ];
        }
      ))

      (lib.mkIf cfg.plymouth.enable {
        boot.plymouth = {
          theme = "ghaf";
          themePackages = [ plymouthTheme ];
        };
      })

      (lib.mkIf config.stylix.targets.gtk.enable {
        environment.etc = {
          "xdg/gtk-3.0/settings.ini".source = gtkSettingsIni;
          "xdg/gtk-4.0/settings.ini".source = gtkSettingsIni;
          "xdg/gtk-3.0/gtk.css".source = gtkCss;
          "xdg/gtk-4.0/gtk.css".source = gtkCss;
        };

        environment.systemPackages = [
          gtkThemePackage
          pkgs.gsettings-desktop-schemas
        ];

        # gsettings needs its schemas compiled onto XDG_DATA_DIRS (unlike
        # `dconf read`, which ignores schemas). These packages install to
        # share/gsettings-schemas/<name>, not share/glib-2.0, so
        # pathsToLink can't reach them - same fix as wireguard-gui.nix.
        environment.sessionVariables.XDG_DATA_DIRS = [
          "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
          "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
          "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}"
        ];

        # Belt-and-suspenders: points GLib straight at a pre-compiled
        # schema cache, bypassing XDG_DATA_DIRS-based schema lookup.
        environment.sessionVariables.GSETTINGS_SCHEMA_DIR =
          pkgs.runCommand "ghaf-gsettings-schemas" { nativeBuildInputs = [ pkgs.glib ]; }
            ''
              mkdir -p $out
              cp ${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas/*.xml $out/
              cp ${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas/*.xml $out/
              cp ${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}/glib-2.0/schemas/*.xml $out/
              glib-compile-schemas $out
            '';

        # GNOME/GTK3-4/libadwaita apps (and COSMIC) read theme settings via
        # gsettings/dconf, not settings.ini - mirrors stylix's home-manager
        # gtk module, as a system-wide dconf default instead of per-user.
        programs.dconf = {
          enable = lib.mkForce true;
          profiles.user.databases = [
            {
              settings."org/gnome/desktop/interface" = {
                gtk-theme = gtkThemeName;
                icon-theme = iconThemeName;
                color-scheme = if cfg.polarity == "dark" then "prefer-dark" else "prefer-light";
                font-name = "${cfg.fonts.sansSerif.name} ${fontSize}";
              };
            }
          ];
        };
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
