# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-initial-setup.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Preselect-Ghaf-themes.patch
  ];
  # Don't install default cosmic themes
  postPatch = oldAttrs.postPatch or "" + ''
    substituteInPlace justfile \
      --replace-fail "find res/themes" "# find res/themes"
  '';
})
