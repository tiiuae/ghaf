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
    #nixpkgs.url = "github:tiiuae/nixpkgs/qemu-10-1-bump";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # A framework for testing ghaf configurations
    ci-test-automation = {
      url = "github:tiiuae/ci-test-automation";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # VM control interface for Ghaf
    ctrl-panel = {
      url = "github:tiiuae/ghaf-ctrl-panel";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        crane.follows = "givc/crane";
      };
    };

    # Development environment management
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    # For building and creating disk images and installers
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For preserving compatibility with non-Flake users
    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
    };

    # Allows us to structure the flake with the NixOS module system
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Where am I?
    flake-root.url = "github:srid/flake-root";

    # flake utility tool for structuring a flake project
    # TODO: should we remove this as it is only used to pin other inputs.
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    # A set of useful nix packages and utilities for ghaf
    ghafpkgs = {
      url = "github:tiiuae/ghafpkgs/8e8a0c707f67443ab9b5f68a646d100dfb954975";
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

    # To ensure that checks are run locally to enforce cleanliness
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    # Ghaf Inter VM communication and control library
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

    # Nvidia Orin support for NixOS
    jetpack-nixos = {
      #url = "github:anduril/jetpack-nixos";
      url = "github:tiiuae/jetpack-nixos/final-stretch-extraConf-gcc13";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For building and managing VMs
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # Building various image types for NixOS
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware specific modules and configurations for NixOS
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
    };

    # Packages managment similar to nixpkgs, applied to flake parts
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts/7013e769c509a97cfe53c5924b45b273021225c3";

    # For preserving data across NixOS rebuilds
    preservation = {
      url = "github:nix-community/preservation";
    };

    # Some nice tips and tricks for NixOS configurations
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # A collection of nixos modules for various different architectures and systems
    systems.url = "github:nix-systems/default";

    # Format all the things
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # A UI for the one true VPN: Wireguard
    wireguard-gui = {
      url = "github:tiiuae/wireguard-gui";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        crane.follows = "givc/crane";
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
