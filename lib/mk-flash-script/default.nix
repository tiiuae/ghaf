# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  isCross =
    hostConfiguration.config.nixpkgs.buildPlatform.system
    != hostConfiguration.config.nixpkgs.hostPlatform.system;
  devicePkgsSystem =
    if isCross
    then "x86_64-linux"
    else "aarch64-linux";
  devicePkgs = jetpack-nixos.legacyPackages.${devicePkgsSystem}.devicePkgsFromNixosConfig hostConfiguration.config;

  inherit (jetpack-nixos.legacyPackages.${devicePkgsSystem}) l4tVersion;

  flashScript = devicePkgs.mkFlashScript {
    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });
    preFlashCommands =
      nixpkgs.lib.optionalString (flash-tools-system == "aarch64-linux") ''
        echo "WARNING! WARNING! WARNING!"
        echo "You are trying to run aarch64-linux hosted version of the flash-script."
        echo "It runs flashing tools with QEMU using user-mode emulation of x86 cpu."
        echo "There are no known reports from anyone who would have gotten this working ever."
        echo "If this fails, YOU HAVE BEEN WARNED, and don't open a bug report!"
        echo ""
      ''
      + hostConfiguration.config.ghaf.hardware.nvidia.orin.flashScriptOverrides.preFlashCommands;
  };

  patchFlashScript =
    builtins.replaceStrings
    [
      "@pzstd@"
      "@sed@"
      "@patch@"
      "@l4tVersion@"
      "@isCross@"
    ]
    [
      "${nixpkgs.legacyPackages.${flash-tools-system}.zstd}/bin/pzstd"
      "${nixpkgs.legacyPackages.${flash-tools-system}.gnused}/bin/sed"
      "${nixpkgs.legacyPackages.${flash-tools-system}.patch}/bin/patch"
      "${l4tVersion}"
      "${
        if isCross
        then "true"
        else "false"
      }"
    ];
in
  nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
    name = "flash-ghaf";
    text = patchFlashScript flashScript;
  }
