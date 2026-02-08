# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.nix-setup;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./nix.nix;

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

  config.nix = {
    inherit (cfg) enable;
    settings = mkIf cfg.enable {
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
    gc = {
      automatic = cfg.automatic-gc.enable;
      dates = "daily";
      options = "--delete-older-than 3d";
    };

    # Set the path and registry so that e.g. nix-shell and repl work
    # TODO this should likely be config.nixpkgs, which has the final overlays
    nixPath = lib.mkIf (cfg.enable && cfg.nixpkgs != null) [ "nixpkgs=${cfg.nixpkgs}" ];

    registry = lib.mkIf (cfg.enable && cfg.nixpkgs != null) {
      nixpkgs.to = {
        type = "path";
        path = cfg.nixpkgs;
      };
    };
  };
}
