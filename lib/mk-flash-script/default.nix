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

  # jetpack-nixos has the cross-compilation set up in a slightly strange way,
  # the packages under x86_64-linux are actually cross-compiled packages for
  # aarch64-linux. So we will get devicePkgs from x86_64-linux if we are cross
  # compiling, otherwise we end up building UEFI firmware etc. binaries used by
  # flash-script natively.
  isCross = hostConfiguration.config.nixpkgs.buildPlatform.system != hostConfiguration.config.nixpkgs.hostPlatform.system;
  devicePkgsSystem =
    if isCross
    then "x86_64-linux"
    else "aarch64-linux";
  devicePkgs = jetpack-nixos.legacyPackages.${devicePkgsSystem}.devicePkgsFromNixosConfig hostConfiguration.config;

  flashScript = devicePkgs.mkFlashScript {
    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });
    inherit (hostConfiguration.config.ghaf.hardware.nvidia.orin.flashScriptOverrides) preFlashCommands;
  };
in
  nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
    name = "flash-ghaf";
    text = flashScript;
  }
