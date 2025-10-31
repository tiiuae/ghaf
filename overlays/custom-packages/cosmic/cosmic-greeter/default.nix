# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Disable network manager in cosmic-greeter
# Ref: https://github.com/pop-os/cosmic-greeter/blob/master/Cargo.toml
{ prev }:
prev.cosmic-greeter.overrideAttrs (oldAttrs: {
  cargoBuildNoDefaultFeatures = true;
  cargoBuildFeatures = [
    "logind"
    # "networkmanager"
    "upower"
  ];
  patches = oldAttrs.patches ++ [
    ./0001-Replace-fallback-background-with-Ghaf-default.patch
  ];
})
