# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  #TODO move this to a standalone function
  #should it live in the library or just as a function file
  mkLaptopConfiguration =
    machineType: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.reference-profiles
          self.nixosModules.laptop
          inputs.lanzaboote.nixosModules.lanzaboote

          #TODO can we move microvm to the profile/laptop-x86?
          self.nixosModules.microvm
          #TODO see the twisted dependencies in common/desktop

          (_: {
            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };
          })
        ] ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${machineType}-${variant}";
      package = hostConfiguration.config.system.build.diskoImages;
    };
in
mkLaptopConfiguration
