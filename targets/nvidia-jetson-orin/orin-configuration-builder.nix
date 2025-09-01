# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "aarch64-linux";

  #TODO move this to a standalone function
  #should it live in the library or just as a function file
  mkOrinConfiguration =
    name: som: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        specialArgs = inputs;
        modules = [
          self.nixosModules.profiles-orin
          {
            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };

            nixpkgs = {
              hostPlatform.system = "aarch64-linux";

              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                #jitsi was deemed insecure because of an obsecure potential security
                #vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                  "qtwebengine-5.15.19"
                ];
              };

              overlays = [ self.overlays.default ];
            };
          }
          (import ./optee.nix { })
        ]
        ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      inherit variant;
      name = "${name}-${som}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
in
mkOrinConfiguration
