# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate NVIDIA Jetson Orin flash script
{
  lib,
  nixpkgs,
  hostConfiguration,
  jetpack-nixos,
  flash-tools,
  flash-tools-system,
  uefi-firmware,
  socType,
}: let
  cfg = hostConfiguration.config.hardware.nvidia-jetpack;
  pkgs = nixpkgs.legacyPackages.aarch64-linux;
  inherit (jetpack-nixos.legacyPackages.aarch64-linux) bspSrc l4tVersion;
  inherit
    (pkgs.callPackages (jetpack-nixos + "/optee.nix") {
      inherit l4tVersion bspSrc;
    })
    buildTOS
    opteeClient
    ;
  flashScript = import (jetpack-nixos + "/flash-script.nix") {
    inherit lib;

    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });

    flashArgs = cfg.flashScriptOverrides.flashArgs;
    partitionTemplate = cfg.flashScriptOverrides.partitionTemplate;

    inherit socType;

    dtbsDir = hostConfiguration.config.hardware.deviceTree.package;

    uefi-firmware = uefi-firmware.override {
      bootLogo = cfg.firmware.uefi.logo;
      debugMode = cfg.firmware.uefi.debugMode;
      errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
      edk2NvidiaPatches = cfg.firmware.uefi.edk2NvidiaPatches;
    };

    tosImage = buildTOS {inherit socType;};

    preFlashCommands = hostConfiguration.config.ghaf.nvidia-jetpack.flashScriptOverrides.preFlashCommands;
  };
in
  nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
    name = "flash-ghaf";
    text = flashScript;
  }
