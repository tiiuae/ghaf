# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Laptop Configuration Builder Library
#
# This module provides a reusable function for building laptop configurations
# that can be consumed by both Ghaf internally and downstream projects.
#
# Usage in downstream projects:
#   let mkLaptopConfiguration = inputs.ghaf.lib.builders.mkLaptopConfiguration inputs.ghaf;
#   in mkLaptopConfiguration "my-laptop" "debug" [...]
{
  self,
  inputs,
  lib ? self.lib,
  system ? "x86_64-linux",
}:
let
  mkLaptopConfiguration =
    machineType: variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        specialArgs = inputs // {
          inherit lib inputs;
        };
        modules = [
          self.nixosModules.profiles-workstation
          {
            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };

            nixpkgs = {
              hostPlatform.system = system;

              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                # jitsi was deemed insecure because of an obscure potential security
                # vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                  "qtwebengine-5.15.19"
                ];
              };

              overlays = [ self.overlays.default ];
            };
          }
        ]
        ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      inherit variant;
      name = "${machineType}-${variant}";
      package = hostConfiguration.config.system.build.ghafImage;
    };
in
mkLaptopConfiguration
