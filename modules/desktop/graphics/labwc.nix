# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  renderers = ["vulkan" "pixman" "egl2"];
in {
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
    renderer = lib.mkOption {
      type = lib.types.enum renderers;
      default = "pixman";
      description = ''
        Which wlroots renderer to use.
        Choose one of: ${lib.concatStringsSep "," renderers}
      '';
    };
    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = ../../../assets/wallpaper.png;
      description = "Path to the wallpaper image";
    };
    frameColouring = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
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
      });
      default = [
        {
          identifier = "foot";
          colour = "#006305";
        }
        # TODO these should reference the VM and not the application that is
        # relayed through waypipe. Ideally this would match using metadata
        # through Wayland security context.
        {
          identifier = "dev.scpp.saca.gala";
          colour = "#027d7b";
        }
        {
          identifier = "chromium-browser";
          colour = "#630505";
        }
        {
          identifier = "org.pwmt.zathura";
          colour = "#122263";
        }
        {
          identifier = "Element";
          colour = "#337aff";
        }
      ];
      description = "List of applications and their frame colours";
    };
    extraAutostart = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "These lines go to the end of labwc autoconfig";
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.window-manager-common.enable = true;

    environment.systemPackages =
      [
        pkgs.labwc
        pkgs.ghaf-openbox-theme
        pkgs.adwaita-icon-theme

        (import ./launchers.nix {inherit pkgs config;})
      ]
      # Grim screenshot tool is used for labwc debug-builds
      ++ lib.optionals config.ghaf.profiles.debug.enable [pkgs.grim];

    # It will create a /etc/pam.d/ file for authentication
    security.pam.services.gtklock = {};

    services.upower.enable = true;
    fonts.fontconfig.defaultFonts.sansSerif = ["Inter"];

    ghaf.graphics.launchers = lib.mkIf config.ghaf.profiles.debug.enable [
      {
        name = "Terminal";
        path = "${pkgs.foot}/bin/foot";
        icon = "${pkgs.icon-pack}/utilities-terminal.svg";
      }
    ];

    # Next 2 services/targets are taken from official weston documentation
    # and adjusted for labwc
    # https://wayland.pages.freedesktop.org/weston/toc/running-weston.html
    systemd.user.services."labwc" = {
      enable = true;
      description = "labwc, a Wayland compositor, as a user service TEST";
      documentation = ["man:labwc(1)"];
      after = ["ghaf-session.service"];
      serviceConfig = {
        # Previously there was "notify" type, but for some reason
        # systemd kills labwc.service because of timeout (even if it is disabled).
        # "simple" works pretty well, so let's leave it.
        Type = "simple";
        #TimeoutStartSec = "60";
        #WatchdogSec = "20";
        # Defaults to journal
        StandardOutput = "journal";
        StandardError = "journal";
        # ExecStart defined in labwc.config.nix
        #GPU pt needs some time to start - labwc fails to restart 3 times in avg.
        # ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        Restart = "on-failure";
        RestartSec = "1";

        # Ivan N: adding openssh into the PATH since it is needed for waypipe to work
        Environment = "PATH=${pkgs.openssh}/bin:$PATH";
      };
      environment = {
        WLR_RENDERER = cfg.renderer;
        # See: https://github.com/labwc/labwc/blob/0.6.5/docs/environment
        XKB_DEFAULT_LAYOUT = "us,fi";
        XKB_DEFAULT_OPTIONS = "XKB_DEFAULT_OPTIONS=grp:alt_shift_toggle";
        XDG_CURRENT_DESKTOP = "wlroots";
        MOZ_ENABLE_WAYLAND = "1";
        XCURSOR_THEME = "breeze_cursors";
        WLR_NO_HARDWARE_CURSORS = "1";
        _JAVA_AWT_WM_NONREPARENTING = "1";
      };
      wantedBy = ["default.target"];
    };

    #Allow video group to change brightness
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video $sys$devpath/brightness", RUN+="${pkgs.coreutils}/bin/chmod a+w $sys$devpath/brightness"
    '';
  };
}
