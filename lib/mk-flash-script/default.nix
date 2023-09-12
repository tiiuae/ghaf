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
  isCross =
    hostConfiguration.config.nixpkgs.buildPlatform.system
    != hostConfiguration.config.nixpkgs.hostPlatform.system;
  devicePkgsSystem =
    if isCross
    then "x86_64-linux"
    else "aarch64-linux";
  devicePkgs = jetpack-nixos.legacyPackages.${devicePkgsSystem}.devicePkgsFromNixosConfig hostConfiguration.config;

  inherit (jetpack-nixos.legacyPackages.${devicePkgsSystem}) l4tVersion;

  pkgsAarch64 =
    if isCross
    then nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform
    else nixpkgs.legacyPackages.aarch64-linux;

  inherit (pkgsAarch64.callPackages ./uefi-firmware.nix {inherit l4tVersion;}) uefi-firmware;

  ghaf-uefi-firmware = uefi-firmware.override ({
      bootLogo = cfg.firmware.uefi.logo;
      debugMode = cfg.firmware.uefi.debugMode;
      errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
      edk2NvidiaPatches = cfg.firmware.uefi.edk2NvidiaPatches;
    }
    // nixpkgs.lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
      inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
    });

  flashScript = devicePkgs.mkFlashScript {
    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });
    uefi-firmware = ghaf-uefi-firmware;
    inherit (hostConfiguration.config.ghaf.hardware.nvidia.orin.flashScriptOverrides) preFlashCommands;
  };

  patchFlashScript =
    builtins.replaceStrings
    [
      "@pzstd@"
      "@sed@"
      "@l4tVersion@"
      "@isCross@"
    ]
    [
      "${nixpkgs.legacyPackages.${flash-tools-system}.zstd}/bin/pzstd"
      "${nixpkgs.legacyPackages.${flash-tools-system}.gnused}/bin/sed"
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
