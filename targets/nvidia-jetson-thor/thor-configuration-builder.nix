# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "aarch64-linux";

  mkThorConfiguration =
    name: som: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        specialArgs = inputs // {
          inherit (self) lib;
        };
        modules = [
          self.nixosModules.profiles-thor
          {
            ghaf = {
              profiles = {
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };

            nixpkgs = {
              hostPlatform.system = system;
              config.allowUnfree = true;
              overlays = [
                self.overlays.default
              ];
            };
          }
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
mkThorConfiguration
