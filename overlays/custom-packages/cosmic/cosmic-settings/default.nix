# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Disable certain settings pages in cosmic-settings
# Ref: https://github.com/pop-os/cosmic-settings/blob/master/cosmic-settings/Cargo.toml
{ prev }:
(prev.cosmic-settings.overrideAttrs (oldAttrs: {
  cargoBuildNoDefaultFeatures = true;
  cargoBuildFeatures = [
    "cosmic-comp-config"
    "a11y"
    "dbus-config"
    "page-about"
    "page-accessibility"
    "page-date"
    "page-default-apps"
    "page-display"
    "page-input"
    "page-region"
    "page-power"
    "page-sound"
    # "page-users"
    "page-legacy-applications"
    # "page-bluetooth"
    "page-networking"
    "page-window-management"
    "page-workspaces"
    "single-instance"
    "wayland"
    "wgpu"
    "xdg-portal"
    "systemd"
  ];
  postPatch = oldAttrs.postPatch or "" + ''
    # Reset to the system theme defaults (the Ghaf theme), not libcosmic's built-in one
    substituteInPlace cosmic-settings/src/pages/desktop/appearance/mod.rs \
      --replace-fail 'ThemeBuilder::dark()' 'Config::system(cosmic::cosmic_theme::DARK_THEME_BUILDER_ID, ThemeBuilder::VERSION).map_or_else(|_| ThemeBuilder::dark(), |c| ThemeBuilder::get_entry(&c).unwrap_or_else(|(_, b)| b))' \
      --replace-fail 'ThemeBuilder::light()' 'Config::system(cosmic::cosmic_theme::LIGHT_THEME_BUILDER_ID, ThemeBuilder::VERSION).map_or_else(|_| ThemeBuilder::light(), |c| ThemeBuilder::get_entry(&c).unwrap_or_else(|(_, b)| b))'
    # The host shares its real DMI (see microvm-host.nix), this allows cosmic-settings to read it
    substituteInPlace cosmic-settings/src/pages/system/info.rs \
      --replace-fail '"/sys/devices/virtual/dmi/id/"' '"/etc/common/dmi/"'
  '';
}))
