# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "PROJ_NAME - Ghaf based configuration";

  nixConfig = {
    extra-trusted-substituters = [
      "https://cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
    ];
    extra-trusted-public-keys = [
      "cache.vedenemo.dev:RGHheQnb6rXGK5v9gexJZ8iWTPX6OcSeS56YeXYzOcg="
      "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
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
    nixos-hardware,
    flake-utils,
  }: let
    systems = with flake-utils.lib.system; [
      x86_64-linux
      riscv64-linux
    ];
  in
    # Combine list of attribute sets together
    nixpkgs.lib.foldr nixpkgs.lib.recursiveUpdate {} [
      (flake-utils.lib.eachSystem systems (system: {
        formatter = nixpkgs.legacyPackages.${system}.alejandra;
      }))

      {
        nixosConfigurations.PROJ_NAME-ghaf-debug = ghaf.nixosConfigurations.microchip-icicle-kit-debug.extendModules {
          modules = [
            {
              #insert your additional modules here e.g.
              # virtualisation.docker.enable = true;
              # users.users."ghaf".extraGroups = ["docker"];
            }
            ({pkgs, ...}: {
              environment.systemPackages = with pkgs; [
                #Add additional system packages here
              ];
            })
          ];
        };
        packages.riscv64-linux.PROJ_NAME-ghaf-debug = self.nixosConfigurations.PROJ_NAME-ghaf-debug.config.system.build.sdImage;
      }
    ];
}
