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
      default = config.ghaf.users.admin.name;
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
    maxDesktops = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Max number of virtual desktops.";
    };
    gtk = lib.mkOption {
      type = lib.types.submodule {
        options = {
          theme = lib.mkOption {
            type = lib.types.str;
            example = "Adwaita";
            description = "Basename of the default theme used by gtk+.";
          };
          iconTheme = lib.mkOption {
            type = lib.types.str;
            example = "Papirus";
            description = "Name of the default icon theme used by gtk+.";
          };
          colorScheme = lib.mkOption {
            type = lib.types.enum [
              "default"
              "prefer-dark"
              "prefer-light"
            ];
            example = "prefer-dark";
            description = "The preferred color scheme for gtk+. Valid values are 'default', 'prefer-dark', 'prefer-light'.";
          };
          fontName = lib.mkOption {
            type = lib.types.str;
            example = "Cantarell";
            description = "The preferred font family.";
          };
          fontSize = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            example = "11";
            description = "The preferred default font size.";
          };
        };
      };
      default = {
        theme = "Adwaita";
        iconTheme = "Papirus";
        colorScheme = "prefer-dark";
        fontName = "Cantarell";
        fontSize = "11";
      };
      description = "Global gtk+ configuration";
    };
    extraAutostart = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "These lines go to the end of labwc autoconfig";
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.login-manager.enable = true;

    environment = {
      systemPackages =
        [
          pkgs.labwc
          pkgs.ghaf-theme
          pkgs.papirus-icon-theme
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
      sessionVariables = {
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
        XDG_STATE_HOME = "$HOME/.local/state";
        XDG_CACHE_HOME = "$HOME/.cache";
        XDG_PICTURES_DIR = "$HOME/Pictures";
        XDG_VIDEOS_DIR = "$HOME/Videos";
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      };
    };

    # Create custom PAM rules
    security.pam.services = {
      gtklock = {
        rules.auth = {
          systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint
          fprintd.args = [ "maxtries=3" ];
        };
      };
      greetd = {
        fprintAuth = false; # User needs to enter password to decrypt home
        rules = {
          account.group = {
            enable = true;
            control = "requisite";
            modulePath = "${pkgs.linux-pam}/lib/security/pam_succeed_if.so";
            order = 10000;
            args = [
              "user"
              "ingroup"
              "video"
            ];
          };
        };
      };
    };

    # Needed for power commands
    security.polkit.enable = true;

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

    # dconf is necessary for gsettings to work
    programs.dconf.enable = true;

    # DBus service for accessing the list of user accounts and information attached to those accounts
    services.accounts-daemon.enable = true;

    ghaf.graphics.launchers = lib.mkIf config.ghaf.profiles.debug.enable [
      {
        name = "Terminal";
        description = "System Terminal";
        path = "${pkgs.foot}/bin/foot";
      }
    ];
  };
}
