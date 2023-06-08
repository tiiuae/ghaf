# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "Ghaf - Documentation and implementation for TII SSRC Secure Technologies Ghaf Framework";

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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    #BUG: https://github.com/NixOS/nixpkgs/issues/235179
    #BUG: https://github.com/NixOS/nixpkgs/issues/235526
    nixpkgs-22-11.url = "github:nixos/nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:nixos/nixos-hardware";
    #TODO: https://github.com/NixOS/nixos-hardware/pull/612
    # tc_linux, HardenOS kernel configs etc. are not part of nixos/nixos-hardware
    # need to have all these in a forked repository
    nixos-hardware-tii.url = "github:tiiuae/nixos-hardware/tii-riscv";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nixos-generators,
    nixos-hardware,
    microvm,
    jetpack-nixos,
    nixpkgs-22-11,
    nixos-hardware-tii
  }: let
    systems = with flake-utils.lib.system; [
      x86_64-linux
      aarch64-linux
      riscv64-linux
    ];
  in
    # Combine list of attribute sets together
    nixpkgs.lib.foldr nixpkgs.lib.recursiveUpdate {} [
      # Documentation
      (flake-utils.lib.eachSystem systems (system: {
        packages = let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          doc = pkgs.callPackage ./docs/doc.nix {};
        };

        formatter = nixpkgs.legacyPackages.${system}.alejandra;
      }))

      # Target configurations
      (import ./targets {inherit self nixpkgs nixos-generators nixos-hardware microvm jetpack-nixos nixpkgs-22-11 nixos-hardware-tii;})

      # Hydra jobs
      (import ./hydrajobs.nix {inherit self;})

      #templates
      (import ./templates {inherit self;})
    ];
}
