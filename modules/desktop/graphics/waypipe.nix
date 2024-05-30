# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.waypipe;
in {
  options.ghaf.waypipe = {
    enable = lib.mkEnableOption "Waypipe";

    port = lib.mkOption {
      type = lib.types.int;
      default = 1100;
      description = ''
        Waypipe port number to listen for incoming connections
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.waypipe = {
      enable = true;
      description = "waypipe";
      after = ["weston.service" "labwc.service"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.waypipe}/bin/waypipe --vsock -s ${toString cfg.port} client";
        Restart = "always";
        RestartSec = "1";
      };
      startLimitIntervalSec = 0;
      wantedBy = ["ghaf-session.target"];
    };
  };
}
