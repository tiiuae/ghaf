# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pulls individual fields out of a ThemeBuilder RON file.
lib:
let
  extractPaletteInner =
    file: variant:
    let
      content = builtins.readFile file;
      afterStart = builtins.elemAt (lib.splitString "palette: ${variant}((" content) 1;
    in
    builtins.elemAt (lib.splitString "\n    )),\n    spacing:" afterStart) 0;
in
{
  # Matches libcosmic's own dark.ron/light.ron shape, and
  # com.system76.CosmicTheme.*.Builder/v2/palette's shape: tagged `Dark((...))`.
  tagged = file: variant: "${variant}((${extractPaletteInner file variant}\n))";
  # Matches com.system76.CosmicTheme.*/v2/palette's shape (no `.Builder`): bare `(...)`, no enum tag.
  untagged = file: variant: "(${extractPaletteInner file variant}\n)";
  # The ThemeBuilder's own `accent: Some(...)` field, unmodified.
  # Matches com.system76.CosmicTheme.*.Builder/v2/accent's shape exactly.
  accent =
    file:
    let
      content = builtins.readFile file;
      afterStart = builtins.elemAt (lib.splitString "accent: " content) 1;
    in
    builtins.elemAt (lib.splitString ",\n    success:" afterStart) 0;
}
