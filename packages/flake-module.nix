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
      packages.doc = callPackage ../docs {
        revision = lib.strings.fileContents ../.version;
        options =
          let
            cfg = lib.nixosSystem {
              # derived from targets/laptop/laptop-configuration-builder.nix + lenovo-x1-carbon-gen10
              modules = [
                self.nixosModules.reference-profiles
                self.nixosModules.disko-debug-partition
                self.nixosModules.hardware-lenovo-x1-carbon-gen11
                self.nixosModules.profiles-workstation
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
}
