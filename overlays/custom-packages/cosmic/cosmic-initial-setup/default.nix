# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-initial-setup.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Preselect-Ghaf-themes.patch
    ./0002-dont-use-secret-agent.patch
  ];
  # Don't install default cosmic themes and layouts
  postPatch = oldAttrs.postPatch or "" + ''
    substituteInPlace justfile \
      --replace-fail "find res/themes" "# find res/themes" \
      --replace-fail "'share' / 'cosmic-layouts'" "'share' / 'cosmic-layouts-unused'"
    # Disable screen reader by default
    substituteInPlace src/page/a11y.rs \
      --replace-fail 'return cosmic::Task::done(Message::ScreenReaderEnabled(true).into());' ""
    # Enable language and location pages
    substituteInPlace src/page/mod.rs \
      --replace-fail '#[cfg(not(feature = "nixos"))]' ""
  '';
})
