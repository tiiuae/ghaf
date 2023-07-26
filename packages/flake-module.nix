# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self, ...}: {
  flake.packages.riscv64-linux.hart-software-services =
    self.nixosConfigurations.microchip-icicle-kit-debug.pkgs.callPackage ./hart-software-services {};
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    inherit (pkgs) callPackage;
  in {
    packages = self.lib.platformPkgs system {
      gala-app = callPackage ./gala {};
      kernel-hardening-checker = callPackage ./kernel-hardening-checker {};
      windows-launcher = callPackage ./windows-launcher {enableSpice = false;};
      windows-launcher-spice = callPackage ./windows-launcher {enableSpice = true;};
      doc = callPackage ../docs {
        revision = lib.strings.fileContents ../.version;
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
