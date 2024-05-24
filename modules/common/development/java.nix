# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.development.java;
in
  with lib; {
    options.ghaf.development.java = {
      enable = mkEnableOption "Java Support";
    };

    config = mkIf cfg.enable {
      programs.java = {
        enable = true;
        package = pkgs.jdk20;
      };
    };
  }