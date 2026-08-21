# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Replaces libcosmic's compiled-in default theme (cosmic-theme/src/model/
# {dark,light}.ron and the accent_blue fallback in theme.rs) with Ghaf's, in
# every COSMIC app that vendors its own copy of libcosmic.
#
# That compiled-in default is only reached if nothing else answers first.
# nixpkgs' libcosmicAppHook wraps every libcosmic app (regardless of whether
# cosmic-settings is installed alongside it) with an XDG_DATA_DIRS entry
# pointing at cosmic-settings' own share/cosmic, which ships upstream's
# com.system76.CosmicTheme.{Dark,Light}(.Builder) as a static system-default
# resource -- that always wins over the compiled default. cosmic-settings is
# patched below to stop installing it, so cosmic-config falls through to the
# compiled default this file already fixes.
{
  # ghaf.theming.cosmic.theme.{dark,light}
  dark,
  light,
  # ghaf.theming.cosmic.themeDefaultPackages
  packages,
}:
_final: prev:
let
  inherit (prev) lib;

  # Pulls the `Dark((...))`/`Light((...))` palette out of a ThemeBuilder RON
  # file's `palette:` field, matching upstream dark.ron/light.ron's shape.
  extractPalette =
    file: variant:
    let
      content = builtins.readFile file;
      startMarker = "palette: ${variant}((";
      endMarker = "\n    )),\n    spacing:";

      afterStart = lib.splitString startMarker content;
      inner =
        if builtins.length afterStart != 2 then
          throw "theme-default-overlay.nix: expected exactly one '${startMarker}' in ${toString file}"
        else
          let
            innerParts = lib.splitString endMarker (builtins.elemAt afterStart 1);
          in
          if builtins.length innerParts != 2 then
            throw "theme-default-overlay.nix: expected exactly one '${endMarker}' after '${startMarker}' in ${toString file}"
          else
            builtins.elemAt innerParts 0;
    in
    "${variant}((${inner}\n))";

  palette = {
    dark = prev.writeText "cosmic-palette-dark.ron" (extractPalette dark "Dark");
    light = prev.writeText "cosmic-palette-light.ron" (extractPalette light "Light");
  };

  patchThemeDefault =
    pkg:
    pkg.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        find_cosmic_theme_matches() {
          local pathGlob=$1 matches
          matches=$(find "$cargoDepsCopy" -path "$pathGlob")
          if [ -z "$matches" ]; then
            echo "theme-default-overlay.nix: no match for $pathGlob under \$cargoDepsCopy" >&2
            exit 1
          fi
          printf '%s' "$matches"
        }

        while IFS= read -r f; do
          install -m0644 ${palette.dark} "$f"
        done <<<"$(find_cosmic_theme_matches '*/cosmic-theme-*/src/model/dark.ron')"

        while IFS= read -r f; do
          install -m0644 ${palette.light} "$f"
        done <<<"$(find_cosmic_theme_matches '*/cosmic-theme-*/src/model/light.ron')"

        while IFS= read -r f; do
          substituteInPlace "$f" \
            --replace-fail "palette.as_ref().accent_blue" "palette.as_ref().accent_green"
        done <<<"$(find_cosmic_theme_matches '*/cosmic-theme-*/src/model/theme.rs')"
      '';
    });

  patched = lib.genAttrs packages (name: patchThemeDefault prev.${name});
in
patched
// lib.optionalAttrs (patched ? cosmic-settings) {
  cosmic-settings = patched.cosmic-settings.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -rf \
        "$out/share/cosmic/com.system76.CosmicTheme.Dark" \
        "$out/share/cosmic/com.system76.CosmicTheme.Dark.Builder" \
        "$out/share/cosmic/com.system76.CosmicTheme.Light" \
        "$out/share/cosmic/com.system76.CosmicTheme.Light.Builder"
    '';
  });
}
