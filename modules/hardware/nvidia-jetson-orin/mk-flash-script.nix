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
      # Taken from
      # https://github.com/anduril/jetpack-nixos/commit/8200da1d7982a36c83fd9000bdc581a9724c9e1c
      #
      # Nvidia's recommended toolchain is gcc9:
      # https://nv-tegra.nvidia.com/r/gitweb?p=tegra/optee-src/nv-optee.git;a=blob;f=optee/atf_and_optee_README.txt;h=591edda3d4ec96997e054ebd21fc8326983d3464;hb=5ac2ab218ba9116f1df4a0bb5092b1f6d810e8f7#l33
      #
      # https://github.com/anduril/jetpack-nixos/pull/98
      # https://github.com/anduril/jetpack-nixos/issues/96
      #
      # NOTE: Using newer version of gcc resulted in unbootable system.
      #
      stdenv = pkgs.gcc9Stdenv;

      inherit l4tVersion bspSrc;
    })
    buildTOS
    ;
  # NOTE: In every jetpack-nixos update, check that this is aligned with the
  #       one from jetpack-nixos/device-pkgs.nix
  flashScript = import (jetpack-nixos + "/flash-script.nix") {
    inherit lib;
    inherit (cfg.flashScriptOverrides) flashArgs partitionTemplate;

    flash-tools = flash-tools.overrideAttrs ({postPatch ? "", ...}: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });

    uefi-firmware = uefi-firmware.override {
      bootLogo = cfg.firmware.uefi.logo;
      debugMode = cfg.firmware.uefi.debugMode;
      errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
      edk2NvidiaPatches = cfg.firmware.uefi.edk2NvidiaPatches;
    }; # TODO: Add support for UEFI capsule authentication

    inherit socType;

    tosImage = buildTOS {
      inherit socType;
      opteePatches = cfg.firmware.optee.patches;
      extraMakeFlags = cfg.firmware.optee.extraMakeFlags;
    };
    inherit (cfg.firmware) eksFile;

    # TODO uefiDefaultKeysDtbo

    dtbsDir = hostConfiguration.config.hardware.deviceTree.package;

    inherit (hostConfiguration.config.ghaf.nvidia-jetpack.flashScriptOverrides) preFlashCommands;
  };
in
  nixpkgs.legacyPackages.${flash-tools-system}.writeShellApplication {
    name = "flash-ghaf";
    text = flashScript;
  }
