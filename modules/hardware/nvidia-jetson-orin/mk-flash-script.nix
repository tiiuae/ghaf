# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  nixpkgs,
  hostConfiguration,
  jetpack-nixos,
  flash-tools-system,
}: let
  cfg = hostConfiguration.config.hardware.nvidia-jetpack;
  inherit (jetpack-nixos.legacyPackages.${flash-tools-system}) flash-tools;
  devicePkgs = jetpack-nixos.legacyPackages.aarch64-linux.devicePkgsFromNixosConfig hostConfiguration.config;
  flashScript = devicePkgs.mkFlashScript {
    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });
    inherit (hostConfiguration.config.ghaf.nvidia-jetpack.flashScriptOverrides) preFlashCommands;
  };
in
  nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
    name = "flash-ghaf";
    text = flashScript;
  }
