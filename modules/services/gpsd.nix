# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.services.gpsd;
in
  with lib; {
    options.ghaf.services.gpsd = {
      enable = mkEnableOption "Service GPS daemon";
    };

    config = mkIf cfg.enable {
      services.gpsd = {
        enable = true;
        nowait = false;
        port = 2947; #Default
        device = "/dev/ttyUSB0";

        /*
        #For nixpkgs 23.05
        listenany = true;
        devices = [
          "/dev/ttyUSB0"
        ];
        */
      };
    };
  }
