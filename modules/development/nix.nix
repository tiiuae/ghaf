# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.development.nix-setup;
in
  with lib; {
    options.ghaf.development.nix-setup = {
      enable = mkEnableOption "Target Nix config options";
    };

    # TODO setup the channels to properly support e.g. nix-shell and repl
    config = mkIf cfg.enable {
      nix.settings.experimental-features = ["nix-command" "flakes"];
      nix.extraOptions = ''
        keep-outputs          = true
        keep-derivations      = true
      '';
    };
  }
