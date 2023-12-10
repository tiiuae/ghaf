# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.ghaf.development.nix-setup;
in
  with lib; {
    options.ghaf.development.nix-setup = {
      enable = mkEnableOption "Target Nix config options";
    };

    config = mkIf cfg.enable {
      nix = {
        settings.experimental-features = ["nix-command" "flakes"];
        extraOptions = ''
                       keep-outputs          = true
          keep-derivations      = true
        '';
        # Set the path and registry so that e.g. nix-shell and repl work
        nixPath = [
          "nixpkgs=${pkgs.path}"
        ];
        registry = {
          nixpkgs.to = {
            type = "path";
            path = inputs.nixpkgs;
          };
        };
      };
    };
  }
