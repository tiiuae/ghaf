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
    renderDevice = mkOption {
      type = types.nullOr types.path;
      default = null;
      defaultText = "null";
      example = "/dev/dri/renderD129";
      description = ''
        Path to the render device to be used by the COSMIC compositor.

        If set, this will be assigned to the `COSMIC_RENDER_DEVICE` environment variable,
        directing COSMIC to use the specified device (e.g., /dev/dri/renderD129).

        This option can be useful in systems with multiple GPUs to explicitly select
        which device the compositor should use.

        If unset, COSMIC will attempt to automatically detect a suitable render device.
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

    autoLogin = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable automatic login.

          When enabled, the system will automatically log in the specified user
          without requiring credentials at the login screen.
        '';
      };

      user = mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ghaf";
        description = ''
          Username to automatically log in as when auto-login is enabled.

          This should correspond to a valid user defined in the system configuration.
        '';
      };
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
      sessionVariables =
        {
          XKB_DEFAULT_LAYOUT = "us,ara,fi";
          XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
        }
        // lib.optionalAttrs (cfg.compositor == "labwc") {
          WLR_NO_HARDWARE_CURSORS = if (cfg.renderer == "pixman") then 1 else 0;
          WLR_RENDERER = cfg.renderer;
          _JAVA_AWT_WM_NONREPARENTING = 1;
          XDG_SESSION_TYPE = "wayland";
        };

      systemPackages = lib.optionals config.ghaf.profiles.debug.enable [ pkgs.ghaf-open ];
    };

    services.displayManager = {
      autoLogin = mkIf cfg.autoLogin.enable {
        enable = true;
        inherit (cfg.autoLogin) user;
      };
    };

    ghaf.graphics = {
      labwc.enable = cfg.compositor == "labwc";
      labwc.autolock.enable = cfg.idleManagement.enable;
      cosmic.enable = cfg.compositor == "cosmic";
    };

    assertions = [
      {
        assertion = !cfg.autoLogin.enable || cfg.autoLogin.user != "";
        message = "autoLogin.user must be set when autoLogin.enable is true.";
      }
    ];
  };
}
