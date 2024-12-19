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
hostConfiguration.pkgs.nvidia-jetpack.flashScript
# nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
#   name = "flash-ghaf";
#   text = "${hostConfiguration.pkgs.nvidia-jetpack.flashScript}";
# }
