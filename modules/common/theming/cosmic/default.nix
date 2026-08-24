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

  extractPalette = import ./extract-palette.nix lib;

  palette = {
    darkV2 = pkgs.writeText "cosmic-palette-dark-v2.ron" (
      extractPalette.untagged cfg.theme.darkV2 "Dark"
    );
    lightV2 = pkgs.writeText "cosmic-palette-light-v2.ron" (
      extractPalette.untagged cfg.theme.lightV2 "Light"
    );
  };

  # com.system76.CosmicTheme.*.Builder/v2/palette wants the same fields but
  # wrapped in the enum tag, matching libcosmic's own dark.ron/light.ron shape.
  builderPalette = {
    darkV2 = pkgs.writeText "cosmic-builder-palette-dark-v2.ron" (
      extractPalette.tagged cfg.theme.darkV2 "Dark"
    );
    lightV2 = pkgs.writeText "cosmic-builder-palette-light-v2.ron" (
      extractPalette.tagged cfg.theme.lightV2 "Light"
    );
  };

  # Only valid for CosmicTheme.*.Builder: the non-Builder accent is the much
  # richer derived Component struct in cfg.accent, not the ThemeBuilder's own
  # plain colour.
  # Builder is what cosmic-settings app requests a "Reset to default".
  builderAccent = {
    darkV2 = pkgs.writeText "cosmic-builder-accent-dark-v2.ron" (
      extractPalette.accent cfg.theme.darkV2
    );
    lightV2 = pkgs.writeText "cosmic-builder-accent-light-v2.ron" (
      extractPalette.accent cfg.theme.lightV2
    );
  };

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

  # Relies on cosmic-settings not shipping its own CosmicTheme.* schemas under
  # $out/share/cosmic (patched out in overlays/custom-packages/cosmic/cosmic-settings),
  # or on those being overridden by this package.
  cosmicThemeConfig =
    pkgs.runCommand "ghaf-cosmic-theme-config" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        settingsDir="$out/share/cosmic/com.system76.CosmicSettings/v1"
        modeDir="$out/share/cosmic/com.system76.CosmicTheme.Mode/v1"
        tkDir="$out/share/cosmic/com.system76.CosmicTk/v1"
        termDir="$out/share/cosmic/com.system76.CosmicTerm/v1"
        themesDir="$out/share/cosmic-themes"
        mkdir -p "$settingsDir" "$modeDir" "$tkDir" "$termDir" "$themesDir"

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

        # System-default palette for apps that read no cosmic-config value at all
        mkdir -p "$out/share/cosmic/com.system76.CosmicTheme.Dark/v2"
        install -m0644 ${palette.darkV2} "$out/share/cosmic/com.system76.CosmicTheme.Dark/v2/palette"
        mkdir -p "$out/share/cosmic/com.system76.CosmicTheme.Light/v2"
        install -m0644 ${palette.lightV2} "$out/share/cosmic/com.system76.CosmicTheme.Light/v2/palette"
        mkdir -p "$out/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v2"
        install -m0644 ${builderPalette.darkV2} "$out/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v2/palette"
        mkdir -p "$out/share/cosmic/com.system76.CosmicTheme.Light.Builder/v2"
        install -m0644 ${builderPalette.lightV2} "$out/share/cosmic/com.system76.CosmicTheme.Light.Builder/v2/palette"

        # System-default accent: the derived Component struct for the apps that
        # actually render it, and the ThemeBuilder's own plain colour for Builder.
        install -m0644 ${cfg.accent.darkV2} "$out/share/cosmic/com.system76.CosmicTheme.Dark/v2/accent"
        install -m0644 ${cfg.accent.lightV2} "$out/share/cosmic/com.system76.CosmicTheme.Light/v2/accent"
        install -m0644 ${builderAccent.darkV2} "$out/share/cosmic/com.system76.CosmicTheme.Dark.Builder/v2/accent"
        install -m0644 ${builderAccent.lightV2} "$out/share/cosmic/com.system76.CosmicTheme.Light.Builder/v2/accent"
      '';
in
{
  _file = ./default.nix;

  options.ghaf.theming.cosmic = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.desktopManager.cosmic.enable;
      defaultText = lib.literalMD "`services.desktopManager.cosmic.enable`";
      description = "Whether to apply shared theming (polarity, icon theme, fonts, accent colours) to COSMIC apps.";
    };

    accent = {
      darkV2 = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v2/accent-dark.ron;
        description = "Path to the derived accent Component RON used in dark mode (com.system76.CosmicTheme.Dark/v2/accent).";
      };
      lightV2 = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v2/accent-light.ron;
        description = "Path to the derived accent Component RON used in light mode (com.system76.CosmicTheme.Light/v2/accent).";
      };
    };

    theme = {
      dark = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v1/dark.ron;
        description = "Path to the full COSMIC theme RON file used in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v1/light.ron;
        description = "Path to the full COSMIC theme RON file used in light mode.";
      };
      darkV2 = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v2/dark.ron;
        description = "Path to the v2-schema COSMIC theme RON file used in dark mode.";
      };
      lightV2 = lib.mkOption {
        type = lib.types.path;
        default = ./themes/v2/light.ron;
        description = "Path to the v2-schema COSMIC theme RON file used in light mode.";
      };
    };

  };

  config = lib.mkIf (themingCfg.enable && cfg.enable) {
    environment = {
      systemPackages = [ (lib.hiPrio cosmicThemeConfig) ];
      # This is normally set by nixpkgs' desktopManager.cosmic.enable. Here we
      # force link so COSMIC apps in other VMs can inherit the theme settings
      # even if the desktop manager as a whole is not enabled.
      pathsToLink = [
        "/share/cosmic"
      ];
    };
  };
}
