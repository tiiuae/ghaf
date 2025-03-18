# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./own-pkgs-overlay.nix
  ];
  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      inherit (pkgs) callPackage;
    in
    {
      #use the pkgs-by-name-for-flake-parts to get the packages
      # exposed to downstream projects
      pkgsDirectory = ./pkgs-by-name;

      #fix these to be the correct packages placement
      packages = self.lib.platformPkgs system {
        doc = callPackage ../docs {
          revision = lib.strings.fileContents ../.version;
          options =
            let
              cfg = lib.nixosSystem {
                # derived from targets/laptop/laptop-configuration-builder.nix + lenovo-x1-carbon-gen10
                modules = [
                  self.nixosModules.reference-profiles
                  self.nixosModules.laptop
                  self.nixosModules.microvm
                  self.nixosModules.disko-debug-partition
                  self.nixosModules.hardware-lenovo-x1-carbon-gen11
                  self.nixosModules.profiles-laptop
                  self.nixosModules.profiles
                  {
                    nixpkgs = {
                      hostPlatform = "x86_64-linux";
                      overlays = [
                        inputs.ghafpkgs.overlays.default
                      ];
                    };
                  }
                ];
              };
            in
            cfg.options;
        };
      };
    };
}
