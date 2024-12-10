# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for laptop devices based on the hardware and usecase profile
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  laptop-configuration = import ./laptop-configuration-builder.nix { inherit lib self inputs; };

  targets = [
    # Laptop Debug configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "debug" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen10.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-extras" "debug" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial-extras.enable = true;
        };
      }
    ])
    (laptop-configuration "dell-latitude-7230" "debug" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7230.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "dell-latitude-7330" "debug" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7330.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])

    # Laptop Release configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "release" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen10.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "release" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-extras" "release" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial-extras.enable = true;
        };
      }
    ])
    (laptop-configuration "dell-latitude-7230" "release" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7230.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "dell-latitude-7330" "release" [
      self.nixosModules.disko-ab-partitions-v1
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7330.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ])
  ];

  flashScript = pkgs.callPackage ../../packages/flash { };
  genPkgWithFlashScript =
    pkg:
    pkgs.linkFarm "ghaf-image" [
      {
        name = "image";
        path = pkg;
      }
      {
        name = "flashScript";
        path = flashScript;
      }
    ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name (genPkgWithFlashScript t.package)) targets
    );
  };
}
