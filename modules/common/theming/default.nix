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

  fontSizeInt = config.stylix.fonts.sizes.applications;
  fontSize = toString fontSizeInt;

  isCross =
    config.ghaf.global-config.platform.buildSystem != config.ghaf.global-config.platform.hostSystem;

  gtkThemePackage = pkgs.adw-gtk3;
  gtkThemeName = "adw-gtk3" + lib.optionalString (cfg.polarity == "dark") "-dark";

  gtkCss = config.lib.stylix.colors {
    # Must be the mustache source text, not a path string - base16.nix's
    # mkTheme treats any string as literal template content.
    template = builtins.readFile "${inputs.stylix}/modules/gtk/gtk.css.mustache";
    extension = ".css";
  };

  gtkSettingsIni = pkgs.writeText "gtk-settings.ini" ''
    [Settings]
    gtk-application-prefer-dark-theme=${if cfg.polarity == "dark" then "true" else "false"}
    ${lib.optionalString cfg.gtkQtTheme.enable "gtk-theme-name=${gtkThemeName}"}
    ${lib.optionalString (iconThemeName != null) "gtk-icon-theme-name=${iconThemeName}"}
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
    ${lib.optionalString cfg.gtkQtTheme.enable "custom_palette=true"}
    ${lib.optionalString (iconThemeName != null) "icon_theme=${iconThemeName}"}
    standard_dialogs=default
    ${lib.optionalString cfg.gtkQtTheme.enable "style=kvantum"}

    [Fonts]
    fixed="${cfg.fonts.monospace.name},${fontSize}"
    general="${cfg.fonts.sansSerif.name},${fontSize}"
  '';

  plymouthThemeScript = import ./plymouth-theme-script.nix {
    inherit lib;
    cfg = cfg.plymouth;
    colors = config.lib.stylix.colors;
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

  imports = [
    inputs.stylix.nixosModules.stylix
    ./cosmic
  ];

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

    logo = lib.mkOption {
      type = lib.types.path;
      default = "${pkgs.ghaf-artwork}/ghaf-logo-512px.png";
      description = ''
        Default Ghaf logo image used across theming (e.g. as the base for the
        Plymouth boot splash logo). Kept as a single option so branding stays
        consistent even where it is used outside of stylix, such as
        ghaf.graphics.boot's firmware (BGRT) logo override.
      '';
    };

    iconTheme = {
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.papirus-icon-theme;
        description = "Icon theme package. If null, stylix icon theming will not be used";
      };
      light = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "Papirus-Light";
        description = "Icon theme name used in light mode";
      };
      dark = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "Papirus-Dark";
        description = "Icon theme name used in dark mode";
      };
    };

    fonts = {
      sansSerif = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.inter;
          description = "Sans-serif font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Inter";
          description = "Sans-serif font family name";
        };
      };

      monospace = {
        package = lib.mkOption {
          type = lib.types.package;
          default = if isCross then pkgs.dejavu_fonts else pkgs.jetbrains-mono;
          description = "Monospace font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = if isCross then "DejaVu Sans Mono" else "JetBrains Mono";
          description = "Monospace font family name";
        };
      };

      console = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          The font used for the virtual consoles. Can be `null`, a font name, or a path to a PSF font file.

          Use `null` to let the kernel choose a built-in font.
        '';
      };

      emoji = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.noto-fonts-color-emoji;
          description = "Emoji font package";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Noto Color Emoji";
          description = "Emoji font family name";
        };
      };
    };

    gtkQtTheme = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to build and apply Ghaf's custom GTK/Qt themes (adw-gtk3
          with the base16 accent colours baked in, and a matching Kvantum Qt
          style).

          When disabled, the system GTK/Qt theme and style are left
          untouched, but polarity (light/dark preference) and font settings
          still apply.
        '';
      };
    };

    plymouth = {
      enable = lib.mkEnableOption "Plymouth (boot splash) global theming";

      logo = lib.mkOption {
        description = "Logo to be used on the boot screen.";
        type = with lib.types; either path package;
        defaultText = lib.literalMD "`ghaf.theming.logo`";
        default = cfg.logo;
      };

      logoBreathing = lib.mkOption {
        description = "Whether to pulse the Plymouth logo's opacity ('breathe') while booting.";
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

      liveUpdates = lib.mkOption {
        description = ''
          Whether to show a second, smaller line of status text below `bootLabel` that
          other processes can update at runtime, e.g. a systemd service reporting that a
          boot stage has finished.

          Any process can send a status string with `plymouth --update="<text>"`; `bootLabel`
          itself is left untouched, so context (e.g. which VM's splash this is) is never lost.
        '';
        type = lib.types.bool;
        default = false;
        example = true;
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
            inherit (cfg.fonts) sansSerif monospace emoji;
            serif = cfg.fonts.sansSerif;
          };

          icons = {
            enable = cfg.iconTheme.package != null;
            inherit (cfg.iconTheme) package light dark;
          };

          # We build our own Plymouth theme below instead, so that we can pulse
          # the logo's opacity ("breathe") rather than spinning it.
          targets.plymouth.enable = false;

          # qt5ct/qt6ct fail to cross-compile
          targets.qt.enable = !isCross;
        };

        # Remove all unused fonts
        fonts.packages = lib.mkForce (
          with cfg.fonts;
          [
            sansSerif.package
            monospace.package
            emoji.package
          ]
        );

        environment.systemPackages = lib.optional (cfg.iconTheme.package != null) cfg.iconTheme.package;

        console.font = cfg.fonts.console;
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
              ${lib.optionalString cfg.gtkQtTheme.enable "cat ${gtkCss} | tee --append $themeDir/gtk-{3,4}.0/gtk.css"}

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
            GTK_THEME=${gtkThemeName}
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
        };

        environment.systemPackages = [ pkgs.gsettings-desktop-schemas ];

        environment.sessionVariables.XDG_DATA_DIRS = [
          "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
          "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
          "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}"
        ];

        environment.sessionVariables.GSETTINGS_SCHEMA_DIR =
          pkgs.runCommand "ghaf-gsettings-schemas" { nativeBuildInputs = [ pkgs.glib ]; }
            ''
              mkdir -p $out
              cp ${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas/*.xml $out/
              cp ${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas/*.xml $out/
              cp ${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}/glib-2.0/schemas/*.xml $out/
              glib-compile-schemas $out
            '';

        programs.dconf = {
          enable = lib.mkForce true;
          profiles.user.databases = [
            {
              settings."org/gnome/desktop/interface" = {
                color-scheme = if cfg.polarity == "dark" then "prefer-dark" else "prefer-light";
                font-name = "${cfg.fonts.sansSerif.name} ${fontSize}";
              };
            }
          ];
        };
      })

      (lib.mkIf (config.stylix.targets.gtk.enable && cfg.gtkQtTheme.enable) {
        environment.etc = {
          "xdg/gtk-3.0/gtk.css".source = gtkCss;
          "xdg/gtk-4.0/gtk.css".source = gtkCss;
        };

        environment.systemPackages = [ gtkThemePackage ];

        programs.dconf.profiles.user.databases = [
          {
            settings."org/gnome/desktop/interface" = {
              gtk-theme = gtkThemeName;
            };
          }
        ];
      })

      (lib.mkIf config.stylix.targets.qt.enable {
        environment.etc = {
          "xdg/qt5ct/qt5ct.conf".source = qtctSettingsIni;
          "xdg/qt6ct/qt6ct.conf".source = qtctSettingsIni;
        };

        qt = {
          enable = lib.mkForce true;
          platformTheme = lib.mkForce "qt5ct";
        };
      })

      (lib.mkIf (config.stylix.targets.qt.enable && cfg.gtkQtTheme.enable) {
        environment.etc."xdg/Kvantum/kvantum.kvconfig".source = kvantumConfig;

        environment.systemPackages = [ kvantumThemePackage ];

        qt.style = lib.mkForce "kvantum";
      })
    ]
  );
}
