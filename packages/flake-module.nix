# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, inputs, ... }:
{
  # flake.packages.x86_64-linux.hart-software-services =
  #   self.nixosConfigurations.microchip-icicle-kit-debug-from-x86_64.pkgs.callPackage
  #     ./hart-software-services
  #     { };
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
        #gala-app = callPackage ./gala { };
        kernel-hardening-checker = callPackage ./kernel-hardening-checker { };
        make-checks = callPackage ./make-checks { };
        #windows-launcher = callPackage ./windows-launcher { enableSpice = false; };
        #windows-launcher-spice = callPackage ./windows-launcher { enableSpice = true; };
        hardware-scan = callPackage ./hardware-scan { };
        #ghaf-screenshot = callPackage ./ghaf-screenshot { };
        #doc = callPackage ../docs {
        #  revision = lib.strings.fileContents ../.version;
        #  options =
        #    let
        #      cfg = lib.nixosSystem {
        #        # derived from targets/laptop/laptop-configuration-builder.nix + lenovo-x1-carbon-gen10
        #        modules = [
        #          self.nixosModules.reference-profiles
        #          self.nixosModules.laptop
        #          inputs.lanzaboote.nixosModules.lanzaboote
        #          self.nixosModules.microvm
        #          self.nixosModules.disko-ab-partitions-v1
        #          {
        #            nixpkgs.hostPlatform = "x86_64-linux";
        #            ghaf.hardware.definition = import ../modules/reference/hardware/lenovo-x1/definitions/x1-gen11.nix;
        #          }
        #        ];
        #      };
        #    in
        #    cfg.options;
        #};
      };
    };
}
