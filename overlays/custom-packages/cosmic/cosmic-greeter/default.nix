# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Disable network manager in cosmic-greeter
# Ref: https://github.com/pop-os/cosmic-greeter/blob/master/Cargo.toml
{ prev }:
prev.cosmic-greeter.overrideAttrs (_oldAttrs: {
  cargoBuildNoDefaultFeatures = true;
  cargoBuildFeatures = [
    "logind"
    # "networkmanager"
    "upower"
  ];
})
