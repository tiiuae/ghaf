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

          #TODO can we move microvm to the laptop-x86 profile?
          self.nixosModules.microvm
          #TODO see the twisted dependencies in common/desktop

          (_: {
            time.timeZone = "Asia/Dubai";

            ghaf = {
              # TODO:Hardware definitions get rid of this generation stuff
              # pass them as modules directly in extramodules
              hardware = {
                inherit generation;
              };

              profiles = {
                laptop-x86.enable = true;
                mvp-user-trial.enable = true;
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
  (lenovo-x1 "gen10" "debug" [self.nixosModules.disko-basic-partition-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "debug" [self.nixosModules.disko-basic-partition-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen10" "release" [self.nixosModules.disko-basic-partition-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "release" [self.nixosModules.disko-basic-partition-v1 self.nixosModules.hw-lenovo-x1])
]
