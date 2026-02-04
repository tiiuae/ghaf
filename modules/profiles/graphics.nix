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

  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  _file = ./graphics.nix;

  options.ghaf.profiles.graphics = {
    enable = mkEnableOption "Graphics profile";
    idleManagement = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable idle management.

          When enabled, the system will automatically manage screen blanking and suspension
          based on user inactivity.

          Disabling this option is the same as setting all idle timeouts to '0'.

          If 'config.ghaf.services.power-manager.suspend.enable' is false, suspension will not occur
          regardless of this setting.
        '';
      };
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
      systemPackages = lib.optionals config.ghaf.profiles.debug.enable [ pkgs.ghaf-open ];
    };

    services.displayManager = {
      autoLogin = mkIf cfg.autoLogin.enable {
        enable = true;
        inherit (cfg.autoLogin) user;
      };
    };

    ghaf.graphics = {
      cosmic.enable = true;
    };

    assertions = [
      {
        assertion = !cfg.autoLogin.enable || cfg.autoLogin.user != "";
        message = "autoLogin.user must be set when autoLogin.enable is true.";
      }
    ];
  };
}
