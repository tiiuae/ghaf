# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.graphics.boot;
in
  with lib; {
    options.ghaf.graphics.boot = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enables graphical boot with plymouth.
        '';
      };
    };

    config = mkIf cfg.enable {
      boot = {
        plymouth = {
          enable = true;
          logo = ../../../assets/ghaf-logo.png;
        };
        # Hide boot log from user completely
        kernelParams = ["quiet" "udev.log_priority=3"];
        consoleLogLevel = 0;
        initrd.verbose = false;
      };
    };
  }
