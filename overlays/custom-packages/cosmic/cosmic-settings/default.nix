# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Disable certain settings pages in cosmic-settings
# Ref: https://github.com/pop-os/cosmic-settings/blob/master/cosmic-settings/Cargo.toml
{ prev }:
(prev.cosmic-settings.overrideAttrs (_oldAttrs: rec {
  src = prev.fetchFromGitHub {
    owner = "kajusnau";
    repo = "cosmic-settings";
    rev = "locale-rs-patch";
    hash = "sha256-OhEXI0Jl/X9GrHqZoKEBOU819r06HJeOR2rXwwS/blk=";
  };
  cargoDeps = prev.rustPlatform.fetchCargoVendor {
    inherit src;
    hash = "sha256-zTUv/duWE6HYraK9874u1xd8TA7POKim0RCzaLtryLk=";
  };
  cargoBuildNoDefaultFeatures = true;
  cargoBuildFeatures = [
    "a11y"
    "dbus-config"
    "page-about"
    "page-accessibility"
    "page-date"
    "page-default-apps"
    "page-display"
    "page-input"
    "page-region"
    # "page-power"
    # "page-sound"
    # "page-users"
    "page-legacy-applications"
    # "page-bluetooth"
    # "page-networking"
    "page-window-management"
    "page-workspaces"
    "single-instance"
    "wayland"
    "wgpu"
    "xdg-portal"
  ];
}))
