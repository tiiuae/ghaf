# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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

    config = mkIf cfg.enable {
      nix.settings.experimental-features = ["nix-command" "flakes"];
      nix.extraOptions = ''
        keep-outputs          = true
        keep-derivations      = true
      '';
    };
  }
