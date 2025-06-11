# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "Ghaf Framework: Documentation and implementation for TII SSRC Secure Technologies";

  nixConfig = {
    substituters = [
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org"
    ];
    extra-trusted-substituters = [
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org"
    ];
    extra-trusted-public-keys = [
      "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    allow-import-from-derivation = false;
  };

  inputs = {
    #TODO: carrying the extra patch(es) until merged to unstable
    #nixpkgs.url = "github:tiiuae/nixpkgs/unstable-tmp-patches";
    #nixpkgs.url = "flake:mylocalnixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ghafpkgs = {
      url = "github:tiiuae/ghafpkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
        flake-compat.follows = "flake-compat";
        crane.follows = "givc/crane";
        devshell.follows = "devshell";
      };
    };

    #
    # Flake and repo structuring configurations
    #
    # Allows us to structure the flake with the NixOS module system
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts/7013e769c509a97cfe53c5924b45b273021225c3";

    flake-root.url = "github:srid/flake-root";

    # Format all the things
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # To ensure that checks are run locally to enforce cleanliness
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    # For preserving compatibility with non-Flake users
    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
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
      # TODO: after https://github.com/astro/microvm.nix/pull/339 is merged
      # go back to
      # url = "github:astro/microvm.nix";
      url = "github:tiiuae/microvm.nix/fix_mkfs_arm64";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    nixos-hardware = {
      #url = "flake:mylocalnixoshw";
      url = "github:NixOS/nixos-hardware";
    };

    jetpack-nixos = {
      #url = "flake:mylocaljetpack";
      #url = "github:anduril/jetpack-nixos/d1c82127de40e85c9c50295f157e1be59a9ad2a6";
      # In this branch these commits have been reverted to fix the problem
      # of the kernel patches not being applied correctly:
      # 33dd57c Select kernel version based on Jetson BSP version
      # 8e3bbfa rebase onto the upstream jetpack
      # TODO: after this problem is fixed in the upstream, go back to final-stretch branch
      # url = "github:tiiuae/jetpack-nixos/final-stretch"
      url = "github:tiiuae/jetpack-nixos/final-stretch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # Security
    #
    impermanence = {
      url = "github:nix-community/impermanence/32b1094d28d5fbedcc85a403bc08c8877b396255";
    };

    givc = {
      url = "github:tiiuae/ghaf-givc";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flake-root.follows = "flake-root";
        treefmt-nix.follows = "treefmt-nix";
        devshell.follows = "devshell";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
      };
    };

    ctrl-panel = {
      url = "github:tiiuae/ghaf-ctrl-panel";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        crane.follows = "givc/crane";
      };
    };

    wireguard-gui = {
      url = "github:tiiuae/wireguard-gui";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        crane.follows = "givc/crane";
      };

    };

    ci-test-automation = {
      url = "github:tiiuae/ci-test-automation";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      lib = import ./lib.nix { inherit inputs; };
    in
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = { inherit lib; };
      }
      {
        # Toggle this to allow debugging in the repl
        # see:https://flake.parts/debug
        debug = false;

        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        imports = [
          ./overlays/flake-module.nix
          ./modules/flake-module.nix
          ./nix/flake-module.nix
          ./packages/flake-module.nix
          ./targets/flake-module.nix
          ./hydrajobs/flake-module.nix
          ./templates/flake-module.nix
          ./tests/flake-module.nix
        ];

        flake.lib = lib;
      };
}
