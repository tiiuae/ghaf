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
  compositors = [
    "labwc"
    "cosmic"
  ];
  renderers = [
    "vulkan"
    "pixman"
    "gles2"
  ];

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
      default = "cosmic";
      description = ''
        Which Wayland compositor to use.

        Choose one of: ${lib.concatStringsSep "," compositors}
      '';
    };
    renderer = lib.mkOption {
      type = lib.types.enum renderers;
      default = "gles2";
      description = ''
        Which wlroots renderer to use.

        Choose one of: ${lib.concatStringsSep "," renderers}
      '';
    };
    idleManagement = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable or disable system idle management using swayidle.

          When enabled, this will handle automatic screen dimming, locking, and suspending.
        '';
      };
    };
    allowSuspend = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Allow the system to suspend. When enabled, the system will suspend via either the suspend icon,
        lid close, or button press.
      '';
    };
  };

  config = mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      extraPackages = mkIf pkgs.stdenv.hostPlatform.isx86_64 [
        pkgs.intel-media-driver
        pkgs.mesa
        pkgs.libGL
        pkgs.vulkan-loader
      ];
    };
    environment = {
      sessionVariables = {
        WLR_RENDERER = cfg.renderer;
        XDG_SESSION_TYPE = "wayland";
        WLR_NO_HARDWARE_CURSORS = if (cfg.renderer == "pixman") then 1 else 0;
        XKB_DEFAULT_LAYOUT = "us,ara,fi";
        XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
        # Set by default in labwc, but possibly not in other compositors
        XDG_CURRENT_DESKTOP = "wlroots";
        _JAVA_AWT_WM_NONREPARENTING = 1;
      };

      systemPackages = lib.optionals config.ghaf.profiles.debug.enable [ pkgs.ghaf-open ];
    };

    ghaf.graphics = {
      labwc.enable = cfg.compositor == "labwc";
      labwc.autolock.enable = cfg.idleManagement.enable;
      cosmic.enable = cfg.compositor == "cosmic";
    };
  };
}
