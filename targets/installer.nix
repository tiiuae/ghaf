# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 (for now) computer installer
{
  self,
  nixpkgs,
  nixos-generators,
  lib,
}: let
  formatModule = nixos-generators.nixosModules.raw-efi;
  inherit (lib.ghaf) installer;
  targets = map installer [
    {
      name = "generic-x86_64-release";
      systemImgCfg = self.nixosConfigurations.generic-x86_64-release;
      modules = [formatModule];
    }
  ];
in {
  nixosConfigurations.installer =
    (installer {
      name = "generic-x86_64-release";
      systemImgCfg = self.nixosConfigurations.generic-x86_64-release;
    })
    .installerImgCfg;
  packages = lib.foldr lib.recursiveUpdate {} (map ({
      name,
      system,
      installerImgDrv,
      ...
    }: {
      ${system}.${name} = installerImgDrv;
    })
    targets);
}
