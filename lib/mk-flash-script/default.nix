# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  nixpkgs,
  hostConfiguration,
  jetpack-nixos,
}:
let
  # Import pkgs for x86_64-linux system
  pkgs = import nixpkgs {
    system = "x86_64-linux";
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
    overlays = [
      jetpack-nixos.overlays.default
      (import "${jetpack-nixos}/overlay-with-config.nix" hostConfiguration.config)
    ];
  };

  # Generate the flash script derivation
  flashScriptDrv = pkgs.nvidia-jetpack.mkFlashScript { };
in
flashScriptDrv

