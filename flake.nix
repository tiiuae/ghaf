# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "Ghaf - Documentation and implementation for TII SSRC Secure Technologies Ghaf Framework";

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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";

    #
    # Flake and repo structuring configurations
    #
    # Allows us to structure the flake with the NixOS module system
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    flake-root.url = "github:srid/flake-root";

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

    nix-fast-build = {
      url = "github:Mic92/nix-fast-build";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    # Dependencies used by other inputs
    systems.url = "github:nix-systems/default";
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
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

    disko = {
      url = "github:nix-community/disko/master";
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
    } {
      # Toggle this to allow debugging in the repl
      # see:https://flake.parts/debug
      debug = false;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        # RISC-V is a target built from cross compilation and is not
        # included as a host build possibility at this point
        # Future HW permitting this can be re-evaluated
        #"riscv64-linux"
      ];

      imports = [
        ./overlays/flake-module.nix
        ./modules/flake-module.nix
        ./nix/flake-module.nix
        ./packages/flake-module.nix
        ./targets/flake-module.nix
        ./hydrajobs/flake-module.nix
        ./templates/flake-module.nix
      ];

      #TODO Fix this
      #flake.nixosModules = with lib;
      #  mapAttrs (_: import)
      #  (flattenTree (rakeLeaves ./modules));

      flake.lib = lib;
    };
}
