# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
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
  formatModule = nixos-generators.nixosModules.raw-efi;
  imx8qm-mek = variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          nixos-hardware.nixosModules.nxp-imx8qm-mek
          (import ../modules/host {
            inherit self microvm netvm;
          })

          {
            # Enable all the default UI applications
            ghaf = {
              profiles = {
                applications.enable = true;
                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
            };
          }

          formatModule
        ]
        ++ (import ../modules/module-list.nix)
        ++ extraModules;
    };
    netvm = "netvm-${name}-${variant}";
  in {
    inherit hostConfiguration netvm;
    name = "${name}-${variant}";
    netvmConfiguration = import ../microvmConfigurations/netvm {
      inherit lib microvm system;
    };
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  debugModules = [];
  targets = [
    (imx8qm-mek "debug" debugModules)
    (imx8qm-mek "release" [])
  ];
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets)
    // builtins.listToAttrs (map (t: lib.nameValuePair t.netvm t.netvmConfiguration) targets);
  packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
