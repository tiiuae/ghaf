# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
      packages.doc =
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
                    inputs.givc.overlays.default
                  ];
                };
              }
            ];
          };
        in
        callPackage ../docs {
          revision = lib.strings.fileContents ../.version;
          inherit (cfg) options;
          inherit (cfg.pkgs) givc-docs;
        };
    };
}
