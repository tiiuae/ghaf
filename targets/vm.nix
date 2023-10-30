# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  nixos-generators,
  microvm,
}: let
  name = "vm";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.vm;
  vm = variant: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          microvm.nixosModules.host
          ../modules/host
          ../modules/virtualization/microvm/microvm-host.nix
          ../modules/virtualization/microvm/netvm.nix

          {
            ghaf = {
              hardware.x86_64.common.enable = true;

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;
              # TODO: NetVM enabled, but it does not include anything specific
              #       for this Virtual Machine target
              virtualization.microvm.netvm.enable = true;

              # Enable all the default UI applications
              profiles = {
                applications.enable = true;
                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
            };
          }
        ]
        ++ (import ../modules/module-list.nix);
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = let inherit ((hostConfiguration.extendModules {modules = [formatModule];})) config; in config.system.build.${config.formatAttr};
  };
  targets = [
    (vm "debug")
    (vm "release")
  ];
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  flake.packages = {
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
