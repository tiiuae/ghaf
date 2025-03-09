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

  laptop-configuration = import ./laptop-configuration-builder.nix { inherit lib self inputs; };
  laptop-installer = import ./laptop-installer-builder.nix { inherit lib self inputs; };

  # setup some commonality between the configurations
  commonModules = [
    self.nixosModules.disko-debug-partition
    self.nixosModules.reference-profiles
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # concatinate modules that are specific to a target
  withCommonModules = specificModules: specificModules ++ commonModules;

  target-configs = [
    # Laptop Debug configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen10.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-carbon-gen12" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen12.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-extras" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial-extras.enable = true;
        };
      }
    ]))
    (laptop-configuration "dell-latitude-7230" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7230.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "dell-latitude-7330" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7330.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "alienware-m18-R2" "debug" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/alienware/alienware-m18.nix;
          virtualization.microvm.guivm.extraModules = [
            (import ../../modules/reference/hardware/alienware/extra-config.nix)
          ];
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))

    # Laptop Release configurations
    (laptop-configuration "lenovo-x1-carbon-gen10" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen10.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-carbon-gen11" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-carbon-gen12" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen12.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "lenovo-x1-extras" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
          reference.profiles.mvp-user-trial-extras.enable = true;
        };
      }
    ]))
    (laptop-configuration "dell-latitude-7230" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7230.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "dell-latitude-7330" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/dell-latitude/definitions/dell-latitude-7330.nix;
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
    (laptop-configuration "alienware-m18-R2" "release" (withCommonModules [
      {
        ghaf = {
          hardware.definition = import ../../modules/reference/hardware/alienware/alienware-m18.nix;
          virtualization.microvm.guivm.extraModules = [
            (import ../../modules/reference/hardware/alienware/extra-config.nix)
          ];
          reference.profiles.mvp-user-trial.enable = true;
        };
      }
    ]))
  ];

  # map all of the defined configurations to an installer image
  target-installers = map (t: laptop-installer t.name t.variant) target-configs;

  targets = target-configs ++ target-installers;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
