# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.nix-setup;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  options.ghaf.nix-setup = {
    enable = mkEnableOption "Target Nix config options";
    nixpkgs = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the nixpkgs repository";
    };
    trusted-users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of trusted users for Nix.";
    };
  };

  config = {
    # TODO for release builds we likely want to set
    # nix = false; to completely disable Nix on target
    nix = mkIf cfg.enable {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        keep-outputs = true;
        keep-derivations = true;
        inherit (cfg) trusted-users;
      };

      # avoid scenario where the host rootfs gets filled
      # with nixos-rebuild ... switch generated excess
      # generations and becomes unbootable
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 3d";
      };

      # Set the path and registry so that e.g. nix-shell and repl work
      # TODO this should likely be config.nixpkgs, which has the final overlays
      nixPath = lib.mkIf (cfg.nixpkgs != null) [ "nixpkgs=${cfg.nixpkgs}" ];

      registry = lib.mkIf (cfg.nixpkgs != null) {
        nixpkgs.to = {
          type = "path";
          path = cfg.nixpkgs;
        };
      };
    };
  };
}
