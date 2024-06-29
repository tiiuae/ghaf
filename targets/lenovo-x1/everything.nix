# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  lib,
  name,
  system,
  ...
}: let
  lenovo-x1 = generation: variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          self.nixosModules.profiles
          self.nixosModules.laptop

          #TODO can we move microvm to the laptop-x86 profile?
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
                  enabled-app-vms = config.ghaf.reference.appvms.enabled-app-vms;
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
    name = "${name}-${generation}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };
in [
  (lenovo-x1 "gen10" "debug" [
    self.nixosModules.disko-basic-partition-v1
    {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";}
  ])
  (lenovo-x1 "gen11" "debug" [
    self.nixosModules.disko-basic-partition-v1
    {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";}
  ])
  (lenovo-x1 "gen10" "release" [
    self.nixosModules.disko-basic-partition-v1
    {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix";}
  ])
  (lenovo-x1 "gen11" "release" [
    self.nixosModules.disko-basic-partition-v1
    {ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix";}
  ])
]
