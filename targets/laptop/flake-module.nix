# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for laptop devices based on the hardware and usecase profile
{
  lib,
  self,
  ...
}: let
  system = "x86_64-linux";

  laptop-configuration = import ./laptop-configuration-builder.nix {inherit lib self;};

  targets = [
    (laptop-configuration "lenovo-x1-carbon-gen10" "debug" [
      self.nixosModules.disko-basic-partition-v1
      {
        ghaf = {
          hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";
          profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" [
      self.nixosModules.disko-basic-partition-v1
      {
        ghaf = {
          hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";
          profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-carbon-gen10" "release" [
      self.nixosModules.disko-basic-partition-v1
      {
        ghaf = {
          hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";
          profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "lenovo-x1-carbon-gen11" "release" [
      self.nixosModules.disko-basic-partition-v1
      {
        ghaf = {
          hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";
          profiles.mvp-user-trial.enable = true;
        };
      }
    ])
    (laptop-configuration "dell-latitude-7230" "debug" [
      self.nixosModules.disko-basic-partition-v1
      {
        ghaf = {
          hardware.definition.configFile = "/definitions/dell-latitude/dell-latitude-7230.nix";
          profiles.mvp-user-trial.enable = true;
        };
      }
    ])
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages.${system} =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
