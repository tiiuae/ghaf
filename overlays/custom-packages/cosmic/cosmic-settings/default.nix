# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Disable certain settings pages in cosmic-settings
# Disabled pages: page-power, page-sound, page-users, page-legacy-applications
# Ref: https://github.com/pop-os/cosmic-settings/blob/master/cosmic-settings/Cargo.toml
{ prev }:
prev.cosmic-settings.overrideAttrs (oldAttrs: {
  cargoBuildFlags = (oldAttrs.cargoBuildFlags or [ ]) ++ [
    "--no-default-features"
    "--features"
    "a11y,dbus-config,single-instance,wgpu,page-accessibility,page-about,page-bluetooth,page-date,page-default-apps,page-display,page-input,page-networking,page-region,page-window-management,page-workspaces,xdg-portal,wayland"
  ];
})
