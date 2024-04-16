# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "PROJ_NAME - Ghaf based configuration";

  nixConfig = {
    substituters = [
      "https://cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-substituters = [
      "https://cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-public-keys = [
      "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
      "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
      "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    ghaf = {
      url = "github:tiiuae/ghaf";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        nixos-hardware.follows = "nixos-hardware";
      };
    };
  };

  outputs = {
    self,
    ghaf,
    nixpkgs,
    flake-utils,
    ...
  }: let
    systems = with flake-utils.lib.system; [
      x86_64-linux
      aarch64-linux
    ];
  in
    # Combine list of attribute sets together
    nixpkgs.lib.foldr nixpkgs.lib.recursiveUpdate {} [
      (flake-utils.lib.eachSystem systems (system: {
        formatter = nixpkgs.legacyPackages.${system}.alejandra;
      }))

      {
        nixosConfigurations.PROJ_NAME-ghaf-debug = ghaf.nixosConfigurations.imx8qm-mek-debug.extendModules {
          modules = [
            {
              #insert your additional modules here e.g.
              # virtualisation.docker.enable = true;
              # users.users."ghaf".extraGroups = ["docker"];
            }
          ];
        };
        packages.aarch64-linux.PROJ_NAME-ghaf-debug = self.nixosConfigurations.PROJ_NAME-ghaf-debug.config.system.build.${self.nixosConfigurations.PROJ_NAME-ghaf-debug.config.formatAttr};
      }
    ];
}
