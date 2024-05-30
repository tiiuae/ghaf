# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.graphics;
  compositors = ["labwc"];
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.ghaf.profiles.graphics = {
    enable = mkEnableOption "Graphics profile";
    compositor = mkOption {
      type = types.enum compositors;
      default = "labwc";
      description = ''
        Which Wayland compositor to use.

        Choose one of: ${lib.concatStringsSep "," compositors}
      '';
    };
  };

  options.ghaf.graphics = {
    launchers = mkOption {
      description = "Labwc application launchers to show in launch bar";
      default = [];
      type =
        types.listOf
        (types.submodule {
          options = {
            name = mkOption {
              description = "Name of the application";
              type = types.str;
            };
            path = mkOption {
              description = "Path to the executable to be launched";
              type = types.path;
            };
            icon = mkOption {
              description = "Path of the icon";
              type = types.path;
            };
          };
        });
    };
    enableDemoApplications = mkEnableOption "some applications for demoing";
  };

  config = mkIf cfg.enable {
    ghaf.graphics = {
      labwc.enable = cfg.compositor == "labwc";
    };
  };
}
