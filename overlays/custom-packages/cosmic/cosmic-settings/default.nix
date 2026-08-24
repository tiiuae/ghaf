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
  # Delete cosmic-settings' own bundled themes
  # libcosmic defaults will be used instead for all COSMIC apps
  # ref: https://github.com/pop-os/libcosmic/blob/2ab0d4c57079f0baf91d24b08a3821984121af62/cosmic-theme/src/model/dark.ron
  postInstall = (oldAttrs.postInstall or "") + ''
    rm -rf "$out"/share/cosmic/com.system76.CosmicTheme*
  '';
}))
