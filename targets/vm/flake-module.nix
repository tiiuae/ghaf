# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) nixos-generators;
  name = "vm";
  system = "x86_64-linux";
  vm =
    variant:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          nixos-generators.nixosModules.vm
          self.nixosModules.microvm
          self.nixosModules.profiles
          self.nixosModules.reference-host-demo-apps
          self.nixosModules.hw-x86_64-generic

          {
            ghaf = {
              hardware.x86_64.common.enable = true;

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                # TODO: NetVM enabled, but it does not include anything specific
                #       for this Virtual Machine target
                microvm.netvm.enable = true;
              };

              host.networking.enable = true;

              # Enable all the default UI applications
              profiles = {
                graphics = {
                  enable = true;
                  renderer = "pixman";
                };
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };

              reference.host-demo-apps.demo-apps.enableDemoApplications = true;
            };

            nixpkgs = {
              hostPlatform.system = "x86_64-linux";

              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                #jitsi was deemed insecure because of an obsecure potential security
                #vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                ];
              };

              overlays = [ self.overlays.default ];
            };
          }
        ];
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  targets = [
    (vm "debug")
    (vm "release")
  ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages = {
      x86_64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
