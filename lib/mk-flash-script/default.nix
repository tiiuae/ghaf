# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  nixpkgs,
  hostConfiguration,
  jetpack-nixos,
  flash-tools-system,
}:
let
  flashSystem = "x86_64-linux";
  pkgs = import nixpkgs {
    system = flashSystem;
    overlays = [
      jetpack-nixos.overlays.default
      (import "${jetpack-nixos}/overlay-with-config.nix" hostConfiguration)
    ];
  };

  inherit (pkgs.nvidia-jetpack) flash-tools;

  flashScript = pkgs.nvidia-jetpack.mkFlashScript flash-tools { };
in
nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
  name = "flash-ghaf";
  text = flashScript;
}
