# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.profiles.graphics;
  compositors = [ "labwc" ];
  renderers = [
    "vulkan"
    "pixman"
    "gles2"
  ];
  ghaf-open = pkgs.callPackage ../../../packages/ghaf-open { };

  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
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
    renderer = lib.mkOption {
      type = lib.types.enum renderers;
      default = "pixman";
      description = ''
        Which wlroots renderer to use.

        Choose one of: ${lib.concatStringsSep "," renderers}
      '';
    };
  };

  options.ghaf.graphics = {
    launchers = mkOption {
      description = "Labwc application launchers to show in launch bar";
      default = [ ];
      type = types.listOf (
        types.submodule {
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
        }
      );
    };
    enableDemoApplications = mkEnableOption "some applications for demoing";
  };

  config = mkIf cfg.enable {
    hardware.graphics.enable = true;
    environment.noXlibs = false;
    environment.sessionVariables = {
      WLR_RENDERER = cfg.renderer;
      XDG_SESSION_TYPE = "wayland";
      WLR_NO_HARDWARE_CURSORS = 1;
      XKB_DEFAULT_LAYOUT = "us,ara,fi";
      XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
      # Set by default in labwc, but possibly not in other compositors
      XDG_CURRENT_DESKTOP = "wlroots";
      _JAVA_AWT_WM_NONREPARENTING = 1;
    };

    environment.systemPackages = lib.optionals config.ghaf.profiles.debug.enable [ ghaf-open ];

    ghaf.graphics = {
      labwc.enable = cfg.compositor == "labwc";
    };
  };
}
