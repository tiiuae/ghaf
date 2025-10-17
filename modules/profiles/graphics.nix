# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    renderer = mkOption {
      type = types.enum renderers;
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
        type = types.nullOr types.str;
        default = null;
        example = "ghaf";
        description = ''
          Username to automatically log in as when auto-login is enabled.

          This should correspond to a valid user defined in the system configuration.
        '';
      };
    };
    # If needed we can add an option to enable networkManager via cosmic,
    # which may be wanted in scenarios where net-vm is not used
    networkManager = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use NetworkManager on the system where graphics profile is applied.";
      };
      applet = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the NetworkManager tray applet (nm-applet)";
        };
        useDbusProxy = mkOption {
          type = types.bool;
          default = true;
          description = ''
            If true, run the applet via a D-Bus proxy to net-vm.
          '';
        };
      };
    };

    # If needed we can add an option to enable bluetooth via cosmic,
    # which may be wanted in scenarios where audio-vm is not used
    bluetooth = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable support for Bluetooth on the system where graphics profile is applied.";
      };
      applet = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the Blueman tray applet";
        };

        useDbusProxy = mkOption {
          type = types.bool;
          default = true;
          description = ''
            If true, run the applet via a D-Bus proxy to audio-vm.
          '';
        };
      };
    };
    proxyAudio = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Proxy audio via a D-Bus proxy to audio-vm

        Also enables the Ghaf audio control applet.
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
