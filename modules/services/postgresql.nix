# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.services.postgresql;
in
  with lib; {
    options.ghaf.services.postgresql = {
      enable = mkEnableOption "Service postgresql";
    };

    config = mkIf cfg.enable {
      services.postgresql = {
        enable = true;
      };
    };
  }
