# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for Lenovo X1 Carbon Gen 11
{
  lib,
  self,
  ...
}: let
  system = "x86_64-linux";

  #TODO move this to a standalone function
  #should it live in the library or just as a function file
  laptop-configuration = machineType: variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          self.nixosModules.profiles
          self.nixosModules.laptop

          #TODO can we move microvm to the profile/laptop-x86?
          self.nixosModules.microvm
          #TODO see the twisted dependencies in common/desktop

          (_: {
            time.timeZone = "Asia/Dubai";

            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };
          })
        ]
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${machineType}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };

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
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages.${system} =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
