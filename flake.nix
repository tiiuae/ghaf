# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    #nixpkgs.url = "github:tiiuae/nixpkgs/nixos-unstable-occulante";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # A framework for testing ghaf configurations
    ci-test-automation = {
      url = "github:tiiuae/ci-test-automation";
      inputs = {
        #nixpkgs.follows = "nixpkgs";
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
      inputs.nixpkgs.follows = "nixpkgs";
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
      # TODO: restore the normal GitHub input after ghafpkgs#369 merges.
      url = "git+https://github.com/tiiuae/ghafpkgs?ref=refs/pull/369/head";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks-nix.follows = "git-hooks-nix";
        flake-compat.follows = "flake-compat";
        crane.follows = "givc/crane";
        devshell.follows = "devshell";
      };
    };

    # Crosvm with Ghaf's swtpm backend. This is a non-flake source input
    # because nixpkgs supplies the package expression and Rust dependencies.
    ghaf-crosvm = {
      url = "git+https://github.com/tiiuae/ghaf-crosvm?submodules=1";
      flake = false;
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
    #
    # TEMPORARILY pinned to a commit rather than the branch head
    givc = {
      url = "github:tiiuae/ghaf-givc";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flake-root.follows = "flake-root";
        ghafpkgs.follows = "ghafpkgs";
        treefmt-nix.follows = "treefmt-nix";
        devshell.follows = "devshell";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
      };
    };

    # GPU passthrough GUI
    gp-gui = {
      url = "github:brianmcgillion/gp-gui";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        flake-root.follows = "flake-root";
        git-hooks-nix.follows = "git-hooks-nix";
        devshell.follows = "devshell";
      };
    };

    # Cooperative CUDA Green Context scheduler used by gpu-vm.
    gpu-partition-manager = {
      url = "github:tiiuae/ghaf-gpu-partition-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nvidia Orin support for NixOS
    jetpack-nixos = {
      #url = "github:anduril/jetpack-nixos";
      # TODO: restore august-rebase after jetpack-nixos#22 merges.
      url = "github:tiiuae/jetpack-nixos/feat/orin-proxy-lifecycle";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For building and managing VMs
    microvm = {
      # TODO: restore the upstream input after microvm.nix#586 merges.
      url = "github:vadika/microvm.nix/feat/crosvm-platform-upstream";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # lsp and cmdline tools for the cli
    nixd = {
      url = "github:nix-community/nixd";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    nix-store-veritysetup-generator = {
      url = "github:tiiuae/ghaf-nix-store-veritysetup-generator/ghaf";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        pre-commit-hooks-nix.follows = "git-hooks-nix";
      };
    };

    # Hardware specific modules and configurations for NixOS
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Packages managment similar to nixpkgs, applied to flake parts
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";

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

    # Hot-plugging USB and PCI devices into Crosvm virtual machines
    ghaf-device-manager = {
      # TODO: restore main after ghaf-device-manager#10 merges.
      url = "github:tiiuae/ghaf-device-manager/feat/export-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hot-plugging devices into QEMU virtual machines
    vhotplug = {
      url = "github:tiiuae/vhotplug";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
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

    # Grants rootless Xwayland integration to wayland compositor
    xwayland-satellite = {
      url = "github:Supreeeme/xwayland-satellite";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # Create the extended lib
      ghafLib = import ./lib { inherit inputs; };
      extendedLib = inputs.nixpkgs.lib.extend ghafLib;
    in
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        # Pass the extended lib via specialArgs for immediate access
        specialArgs = {
          lib = extendedLib;
        };
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
          ./lib/builders/flake-module.nix
          ./modules/flake-module.nix
          ./nix/flake-module.nix
          ./packages/flake-module.nix
          ./targets/flake-module.nix
          ./tests/flake-module.nix
        ];

        # Export the extended lib for explicit use
        flake.lib = extendedLib;
      };
}
