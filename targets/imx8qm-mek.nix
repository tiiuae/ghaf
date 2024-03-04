# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# i.MX8QuadMax Multisensory Enablement Kit
{
  self,
  lib,
  nixos-generators,
  nixos-hardware,
  microvm,
}: let
  name = "imx8qm-mek";
  system = "aarch64-linux";
  imx8qm-mek = variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          microvm.nixosModules.host
          nixos-generators.nixosModules.raw-efi
          nixos-hardware.nixosModules.nxp-imx8qm-mek
          self.nixosModules.common
          self.nixosModules.desktop
          self.nixosModules.host
          self.nixosModules.microvm

          {
            ghaf = {
              virtualization.microvm-host.enable = true;
              host.networking.enable = true;
              # TODO: NetVM enabled, but it does not include anything specific
              #       for iMX8
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
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  debugModules = [];
  targets = [
    (imx8qm-mek "debug" debugModules)
    (imx8qm-mek "release" [])
  ];
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  flake.packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
