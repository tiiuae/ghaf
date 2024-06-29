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

  mvp-definition = machineType: variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          self.nixosModules.profiles
          self.nixosModules.laptop

          #TODO can we move microvm to the profile/laptop-x86?
          self.nixosModules.microvm
          #TODO see the twisted dependencies in common/desktop

          ({config, ...}: {
            time.timeZone = "Asia/Dubai";

            ghaf = {
              profiles = {
                mvp-user-trial.enable = true;

                laptop-x86 = {
                  enable = true;
                  netvmExtraModules = [self.nixosModules.reference-services];
                  guivmExtraModules = [self.nixosModules.reference-programs];
                  inherit (config.ghaf.reference.appvms) enabled-app-vms;
                };

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
    (mvp-definition "lenovo-x1-carbon-gen10" "debug" [
      self.nixosModules.disko-basic-partition-v1
      {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";}
    ])
    (mvp-definition "lenovo-x1-carbon-gen11" "debug" [
      self.nixosModules.disko-basic-partition-v1
      {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";}
    ])
    (mvp-definition "lenovo-x1-carbon-gen10" "release" [
      self.nixosModules.disko-basic-partition-v1
      {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";}
    ])
    (mvp-definition "lenovo-x1-carbon-gen11" "release" [
      self.nixosModules.disko-basic-partition-v1
      {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";}
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
