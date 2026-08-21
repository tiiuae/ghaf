# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# COSMIC-specific theming: accent colours, the Ghaf theme RON, and the
# compiled-in libcosmic defaults. Layered on top of the shared stylix theming
# in ../default.nix.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  themingCfg = config.ghaf.theming;
  cfg = themingCfg.cosmic;

  iconThemeName =
    if themingCfg.polarity == "dark" then themingCfg.iconTheme.dark else themingCfg.iconTheme.light;

  cosmicInterfaceFont = pkgs.writeText "cosmic-interface-font.ron" ''
    (
        family: "${themingCfg.fonts.sansSerif.name}",
        weight: Normal,
        stretch: Normal,
        style: Normal,
    )
  '';

  cosmicMonospaceFont = pkgs.writeText "cosmic-monospace-font.ron" ''
    (
        family: "${themingCfg.fonts.monospace.name}",
        weight: Normal,
        stretch: Normal,
        style: Normal,
    )
  '';

  cosmicThemeConfig =
    pkgs.runCommand "ghaf-cosmic-theme-config" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        settingsDir="$out/share/cosmic/com.system76.CosmicSettings/v1"
        modeDir="$out/share/cosmic/com.system76.CosmicTheme.Mode/v1"
        tkDir="$out/share/cosmic/com.system76.CosmicTk/v1"
        termDir="$out/share/cosmic/com.system76.CosmicTerm/v1"
        themesDir="$out/share/cosmic-themes"
        mkdir -p "$settingsDir" "$modeDir" "$tkDir" "$termDir" "$themesDir"

        install -m0644 ${cfg.accentPalette.dark} "$settingsDir/accent_palette_dark.ron"
        install -m0644 ${cfg.accentPalette.light} "$settingsDir/accent_palette_light.ron"

        printf '%s' ${if themingCfg.polarity == "dark" then "true" else "false"} > "$modeDir/is_dark"

        ${lib.optionalString (
          iconThemeName != null
        ) ''printf '"%s"' "${iconThemeName}" > "$tkDir/icon_theme"''}
        install -m0644 ${cosmicInterfaceFont} "$tkDir/interface_font"
        install -m0644 ${cosmicMonospaceFont} "$tkDir/monospace_font"

        printf '"%s"' "${themingCfg.fonts.monospace.name}" > "$termDir/font_name"

        install -m0644 ${cfg.theme.dark} "$themesDir/ghaf-dark.ron"
        install -m0644 ${cfg.theme.light} "$themesDir/ghaf-light.ron"
        install -m0644 ${pkgs.ghaf-artwork}/1600px-Ghaf_logo.png "$themesDir/ghaf-dark.png"
        magick "$themesDir/ghaf-dark.png" -resize 30% "$themesDir/ghaf-dark.png"
        ln -s "$themesDir/ghaf-dark.png" "$themesDir/ghaf-light.png"
      '';
in
{
  _file = ./default.nix;

  options.ghaf.theming.cosmic = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.desktopManager.cosmic.enable;
      defaultText = lib.literalMD "`services.desktopManager.cosmic.enable`";
      description = "Whether to apply shared theming (polarity, icon theme, fonts, accent colours) to the COSMIC desktop.";
    };

    accentPalette = {
      dark = lib.mkOption {
        type = lib.types.path;
        default = ./accent-palette-dark.ron;
        description = "Path to the COSMIC accent colour palette RON file used in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.path;
        default = ./accent-palette-light.ron;
        description = "Path to the COSMIC accent colour palette RON file used in light mode.";
      };
    };

    theme = {
      dark = lib.mkOption {
        type = lib.types.path;
        default = ./ghaf-dark.ron;
        description = "Path to the full COSMIC theme RON file used in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.path;
        default = ./ghaf-light.ron;
        description = "Path to the full COSMIC theme RON file used in light mode.";
      };
    };

    themeDefaultPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cosmic-greeter" # Greeter can't display user configured themes prior to login
        "cosmic-store" # Store runs in flatpak-vm, where user configs are unavailable

        # 'Restore to default' will restore to Ghaf defaults
        # Also we remove the share/cosmic theme defaults which are added to every
        # cosmic app via libcosmicAppHook in nixpkgs upstream
        "cosmic-settings"
      ];
      description = ''
        COSMIC packages to patch so their vendored copy of libcosmic falls
        back to Ghaf's theme instead of upstream's.
        Useful for apps that read no cosmic-config value at all or don't have access
        to the user's config dir.

        See ./theme-default-overlay.nix.
      '';
    };
  };

  config = lib.mkIf (themingCfg.enable && cfg.enable) {
    # We shouldn't do this here but it makes more sense
    # than having these be global without theming enabled
    nixpkgs.overlays = [
      (import ./theme-default-overlay.nix {
        dark = cfg.theme.dark;
        light = cfg.theme.light;
        packages = cfg.themeDefaultPackages;
      })
    ];

    environment = {
      systemPackages = [ cosmicThemeConfig ];
      # This is normally set by nixpkgs' desktopManager.cosmic.enable. Here we
      # force link so COSMIC apps in other VMs can inherit the theme settings
      # even if the desktop manager as a whole is not enabled.
      pathsToLink = [
        "/share/cosmic"
      ];
    };
  };
}
