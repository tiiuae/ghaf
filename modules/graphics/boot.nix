# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.graphics.boot;
in
{
  options.ghaf.graphics.boot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enables graphical boot with plymouth.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      plymouth = {
        enable = true;
        logo = "${pkgs.ghaf-artwork}/ghaf-logo.png";
      };
      # Hide boot log from user completely
      kernelParams = [
        "quiet"
        "udev.log_priority=3"
      ];
      consoleLogLevel = 0;
      initrd.verbose = false;
    };
  };
}
