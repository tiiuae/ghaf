# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.graphics;
in
  with lib; {
    options.ghaf.profiles.graphics = {
      enable = mkEnableOption "Graphics profile";
    };

    config = mkIf cfg.enable {
      ghaf.graphics.enable = true;
    };
  }
