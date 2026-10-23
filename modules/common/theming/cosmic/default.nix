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

  # hiPrio so these keys override cosmic-settings' own CosmicTheme.* defaults.
  cosmicThemeConfig = pkgs.runCommand "ghaf-cosmic-theme-config" { } ''
    modeDir="$out/share/cosmic/com.system76.CosmicTheme.Mode/v1"
    tkDir="$out/share/cosmic/com.system76.CosmicTk/v1"
    termDir="$out/share/cosmic/com.system76.CosmicTerm/v1"
    themesDir="$out/share/cosmic-themes"
    mkdir -p "$modeDir" "$tkDir" "$termDir" "$themesDir"
    printf '%s' ${if themingCfg.polarity == "dark" then "true" else "false"} > "$modeDir/is_dark"
    printf false > "$modeDir/auto_switch"
    ${lib.optionalString (
      iconThemeName != null
    ) ''printf '"%s"' "${iconThemeName}" > "$tkDir/icon_theme"''}
    install -m0644 ${cosmicInterfaceFont} "$tkDir/interface_font"
    install -m0644 ${cosmicMonospaceFont} "$tkDir/monospace_font"
    printf '"%s"' "${themingCfg.fonts.monospace.name}" > "$termDir/font_name"
    install -m0644 ${cfg.theme.dark} "$themesDir/ghaf-dark.ron"
    install -m0644 ${cfg.theme.light} "$themesDir/ghaf-light.ron"
    ${lib.getExe' pkgs.buildPackages.imagemagick "magick"} ${pkgs.ghaf-artwork}/1600px-Ghaf_logo.png -resize 30% "$themesDir/ghaf-dark.png"
    ln -s ghaf-dark.png "$themesDir/ghaf-light.png"
    ${lib.getExe pkgs.buildPackages.ghaf-cosmic-theme} ${cfg.theme.dark} com.system76.CosmicTheme.Dark "$out/share"
    ${lib.getExe pkgs.buildPackages.ghaf-cosmic-theme} ${cfg.theme.light} com.system76.CosmicTheme.Light "$out/share"
    ${lib.getExe pkgs.buildPackages.ghaf-cosmic-theme-v1} ${cfg.theme.dark} com.system76.CosmicTheme.Dark "$out/share"
    ${lib.getExe pkgs.buildPackages.ghaf-cosmic-theme-v1} ${cfg.theme.light} com.system76.CosmicTheme.Light "$out/share"
    # Apps read this key, but the cosmic-theme ghaf-cosmic-theme builds against predates it.
    for v in Dark Light; do printf false > "$out/share/cosmic/com.system76.CosmicTheme.$v/v2/frosted_maximized_apps"; done
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

    # ThemeBuilder RON in whatever schema the packaged COSMIC version expects;
    # update these alongside COSMIC rather than keeping older versions around.
    theme = {
      dark = lib.mkOption {
        type = lib.types.path;
        default = ./themes/dark.ron;
        description = "Path to the COSMIC ThemeBuilder RON file used in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.path;
        default = ./themes/light.ron;
        description = "Path to the COSMIC ThemeBuilder RON file used in light mode.";
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
