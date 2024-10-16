# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.labwc;
in
{
  options.ghaf.graphics.labwc = {
    enable = lib.mkEnableOption "labwc";
    autolock = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable screen autolocking.";
      };
      duration = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Timeout for screen autolock in seconds.";
      };
    };
    autologinUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.ghaf.users.accounts.user;
      description = ''
        Username of the account that will be automatically logged in to the desktop.
        If unspecified, the login manager is shown as usual.
      '';
    };
    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = "${pkgs.ghaf-artwork}/ghaf-desert-sunset.jpg";
      description = "Path to the wallpaper image";
    };
    frameColouring = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            identifier = lib.mkOption {
              type = lib.types.str;
              example = "foot";
              description = "Identifier of the application";
            };
            colour = lib.mkOption {
              type = lib.types.str;
              example = "#006305";
              description = "Colour of the window frame";
            };
          };
        }
      );
      default = [
        {
          identifier = "foot";
          colour = "#006305";
        }
      ];
      description = "List of applications and their frame colours";
    };
    securityContext = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            identifier = lib.mkOption {
              type = lib.types.str;
              description = "The identifier attached to the security context";
            };
            color = lib.mkOption {
              type = lib.types.str;
              example = "#006305";
              description = "Window frame color";
            };
          };
        }
      );
      default = [ ];
      description = "Wayland security context settings";
    };
    extraAutostart = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "These lines go to the end of labwc autoconfig";
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.login-manager.enable = true;

    environment.systemPackages =
      [
        pkgs.labwc
        pkgs.ghaf-theme
        pkgs.adwaita-icon-theme

        (import ./launchers.nix { inherit pkgs config; })
      ]
      # Grim screenshot tool is used for labwc debug-builds
      # satty and slurp add some functionality to bring it
      # a more modern selection tool
      ++ lib.optionals config.ghaf.profiles.debug.enable [
        pkgs.grim
        pkgs.satty
        pkgs.slurp
      ];

    # It will create a /etc/pam.d/ file for authentication
    security.pam.services.gtklock = { };

    systemd.user.targets.ghaf-session = {
      enable = true;
      description = "Ghaf labwc session";
      unitConfig = {
        BindsTo = [ "graphical-session.target" ];
        After = [ "graphical-session-pre.target" ];
        Wants = [ "graphical-session-pre.target" ];
      };
    };

    services.upower.enable = true;
    fonts.fontconfig.defaultFonts.sansSerif = [ "Inter" ];

    ghaf.graphics.launchers = lib.mkIf config.ghaf.profiles.debug.enable [
      {
        name = "Terminal";
        description = "System Terminal";
        path = "${pkgs.foot}/bin/foot";
        icon = "${pkgs.icon-pack}/utilities-terminal.svg";
      }
    ];
  };
}
