# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.nix-setup;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    ;
in
{
  options.ghaf.development.nix-setup = {
    enable = mkEnableOption "Target Nix config options";
    nixpkgs = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the nixpkgs repository";
    };
    automatic-gc = {
      enable = mkEnableOption "Enable automatic garbage collection";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          keep-outputs = true;
          keep-derivations = true;
        };

        # avoid scenario where the host rootfs gets filled
        # with nixos-rebuild ... switch generated excess
        # generations and becomes unbootable
        gc = mkIf cfg.automatic-gc.enable {
          automatic = true;
          dates = "daily";
          options = "--delete-older-than 3d";
        };

        # Set the path and registry so that e.g. nix-shell and repl work
        nixPath = mkIf (cfg.nixpkgs != null) [ "nixpkgs=${cfg.nixpkgs}" ];

        registry = mkIf (cfg.nixpkgs != null) {
          nixpkgs.to = {
            type = "path";
            path = cfg.nixpkgs;
          };
        };
      };
    })

    (mkIf (!cfg.enable) {
      nix = {
        enable = lib.mkForce false;
        gc.automatic = lib.mkForce false;
      };
    })
  ];
}
