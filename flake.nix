# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "Ghaf Framework: Documentation and implementation for TII SSRC Secure Technologies";

  nixConfig = {
    substituters = [
      "https://prod-cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-substituters = [
      "https://prod-cache.vedenemo.dev"
      "https://cache.ssrcdevops.tii.ae"
      "https://ghaf-dev.cachix.org"
      "https://cache.nixos.org/"
    ];
    extra-trusted-public-keys = [
      "prod-cache.vedenemo.dev~1:JcytRNMJJdYJVQCYwLNsrfVhct5dhCK2D3fa6O1WHOI="
      "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
      "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    #TODO: carrying the extra patch(es) until merged to unstable
    nixpkgs.url = "github:tiiuae/nixpkgs/nixos-unstable-gbenchmark";
    #nixpkgs.url = "flake:mylocalnixpkgs";
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ghafpkgs = {
      url = "github:tiiuae/ghafpkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
        flake-compat.follows = "flake-compat";
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
        nixpkgs-stable.follows = "nixpkgs";
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
      #url = "github:anduril/jetpack-nixos
      url = "github:anduril/jetpack-nixos/793716c1ca29a1be6d9bea84296a933c4acdddc1";
      #inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # Security
    #
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-parts.follows = "flake-parts";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
        flake-compat.follows = "flake-compat";
      };
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    givc = {
      url = "github:tiiuae/ghaf-givc/be24afa09e310546ea84832994e59efb0272c303";
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
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      lib = import ./lib.nix { inherit inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
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
        ./tests/flake-module.nix
      ];

      flake.lib = lib;
    };
}
