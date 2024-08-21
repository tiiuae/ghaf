# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  flake.packages.x86_64-linux.hart-software-services =
    self.nixosConfigurations.microchip-icicle-kit-debug-from-x86_64.pkgs.callPackage
      ./hart-software-services
      { };
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      inherit (pkgs) callPackage;
    in
    {
      packages = self.lib.platformPkgs system {
        gala-app = callPackage ./gala { };
        kernel-hardening-checker = callPackage ./kernel-hardening-checker { };
        make-checks = callPackage ./make-checks { };
        windows-launcher = callPackage ./windows-launcher { enableSpice = false; };
        windows-launcher-spice = callPackage ./windows-launcher { enableSpice = true; };
        hardware-scan = callPackage ./hardware-scan { };
        #ctrl-panel = callPackage self.ctrl-panel.packages.default {};
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
