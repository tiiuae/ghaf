# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  self,
  ...
}: let
  inherit (inputs) microvm nixos-generators;
  name = "vm";
  system = "x86_64-linux";
  vm = variant: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules = [
        microvm.nixosModules.host
        nixos-generators.nixosModules.vm
        self.nixosModules.common
        self.nixosModules.desktop
        self.nixosModules.host
        self.nixosModules.microvm

        {
          ghaf = {
            hardware.x86_64.common.enable = true;

            virtualization.microvm-host.enable = true;
            virtualization.microvm-host.networkSupport = true;
            host.networking.enable = true;
            # TODO: NetVM enabled, but it does not include anything specific
            #       for this Virtual Machine target
            virtualization.microvm.netvm.enable = true;

            # Enable all the default UI applications
            profiles = {
              applications.enable = true;
              release.enable = variant == "release";
              debug.enable = variant == "debug";
            };
          };
        }
      ];
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  targets = [
    (vm "debug")
    (vm "release")
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages = {
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
