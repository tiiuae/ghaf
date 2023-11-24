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
      "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
      "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    #
    # Flake and repo structuring configurations
    #
    # Allows us to structure the flake with the NixOS module system
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    flake-root.url = "github:srid/flake-root";

    lib-extras = {
      url = "github:aldoborrero/lib-extras";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-root.follows = "flake-root";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Format all the things
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # To ensure that checks are run locally to enforce cleanliness
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };

    # For preserving compatibility with non-Flake users
    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
    };

    #TODO Delete this
    flake-utils.url = "github:numtide/flake-utils";

    # Used to evaluate a flake outputs all at once
    devour-flake = {
      url = "github:srid/devour-flake";
      flake = false;
    };

    #
    # Target Building and services
    #
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:astro/microvm.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # Security
    #
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.3.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-parts.follows = "flake-parts";
        pre-commit-hooks-nix.follows = "pre-commit-hooks-nix";
        flake-compat.follows = "flake-compat";
      };
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    lib = import ./lib.nix {inherit inputs;};
  in
    flake-parts.lib.mkFlake
    {
      inherit inputs;
      specialArgs = {
        inherit lib;
      };
    } {
      # Toggle this to allow debugging in the repl
      # see:https://flake.parts/debug
      debug = false;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
      ];

      imports = [
        ./nix
        ./packages
        ./targets
        ./hydrajobs.nix
        ./templates
      ];

      #TODO Fix this
      #flake.nixosModules = with lib;
      #  mapAttrs (_: import)
      #  (flattenTree (rakeLeaves ./modules));

      flake.lib = lib;
    };
}
