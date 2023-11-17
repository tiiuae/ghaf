# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    inherit (lib.flakes) platformPkgs;
    inherit (pkgs) callPackage;
  in {
    packages = platformPkgs system {
      gala-app = callPackage ./gala {};
      windows-launcher = callPackage ./windows-launcher {enableSpice = false;};
      windows-launcher-spice = callPackage ./windows-launcher {enableSpice = true;};
      doc = callPackage ../docs {
        revision = lib.ghaf-version;
        # options = ;
        # TODO Add the options in from the self.nixosModules
        # The below is not needed anymore to setoptions
        #
        # options = let
        #           cfg = nixpkgs.lib.nixosSystem {
        #             inherit system;
        #             modules =
        #               lib.ghaf.modules
        #               ++ [
        #                 jetpack-nixos.nixosModules.default
        #                 microvm.nixosModules.host
        #                 lanzaboote.nixosModules.lanzaboote
        #               ];
        #           };
        #         in
        #           cfg.options;
      };
    };
  };
}
