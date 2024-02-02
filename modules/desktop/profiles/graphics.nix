# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.graphics;
  compositors = ["weston" "gnome" "labwc"];
in
  with lib; {
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

    options.ghaf.graphics = with lib; {
      launchers = mkOption {
        description = "Labwc application launchers to show in launch bar";
        default = [];
        type = with types;
          listOf
          (submodule {
            options.name = mkOption {
              description = "Name of the application";
              type = str;
            };
            options.path = mkOption {
              description = "Path to the executable to be launched";
              type = path;
            };
            options.icon = mkOption {
              description = "Path of the icon";
              type = path;
            };
          });
      };
      enableDemoApplications = mkEnableOption "some applications for demoing";
    };

    config = mkIf cfg.enable {
      ghaf.graphics.weston.enable = cfg.compositor == "weston";
      ghaf.graphics.gnome.enable = cfg.compositor == "gnome";
      ghaf.graphics.labwc.enable = cfg.compositor == "labwc";
    };
  }
