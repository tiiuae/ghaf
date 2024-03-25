# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  autostart =
    pkgs.writeScriptBin "labwc-autostart" ''
      # Import WAYLAND_DISPLAY variable to make it available to waypipe and other systemd services
      ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY 2>&1 &

      # Set the wallpaper.
      ${pkgs.swaybg}/bin/swaybg -m fill -i ${cfg.wallpaper} >/dev/null 2>&1 &

      # Configure output directives such as mode, position, scale and transform.
      ${pkgs.kanshi}/bin/kanshi >/dev/null 2>&1 &

      # Launch the top task bar.
      ${pkgs.waybar}/bin/waybar -s /etc/waybar/style.css -c /etc/waybar/config >/dev/null 2>&1 &

      # Enable notifications.
      ${pkgs.mako}/bin/mako >/dev/null 2>&1 &

      ${lib.optionalString cfg.lock.enable ''
        # Lock screen after 5 minutes
        ${pkgs.swayidle}/bin/swayidle -w timeout 300 \
        '${pkgs.swaylock-effects}/bin/swaylock -f -c 000000 \
        --clock --indicator --indicator-radius 150 --inside-ver-color 5ac379' &
      ''}
    ''
    + cfg.extraAutostart;
  rcXml = ''
    <?xml version="1.0"?>
    <labwc_config>
    <core><gap>10</gap></core>
    <keyboard>
      <default />
    </keyboard>
    <mouse><default /></mouse>
    <windowRules>
      ${lib.concatStringsSep "\n" (map (rule: ''
        <windowRule identifier="${rule.identifier}" borderColor="${rule.colour}" serverDecoration="yes" skipTaskbar="no"  />
      '')
      cfg.frameColouring)}
    </windowRules>
    </labwc_config>
  '';

  menuXml = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <openbox_menu>
      <menu id="client-menu">
        <item label="Minimize">
          <action name="Iconify" />
        </item>
        <item label="Maximize">
          <action name="ToggleMaximize" />
        </item>
        <item label="Fullscreen">
          <action name="ToggleFullscreen" />
        </item>
        <item label="Decorations">
          <action name="ToggleDecorations" />
        </item>
        <item label="AlwaysOnTop">
          <action name="ToggleAlwaysOnTop" />
        </item>
      </menu>
    </openbox_menu>
  '';
  launchers = pkgs.callPackage ./launchers.nix {inherit config;};
in {
  options.ghaf.graphics.labwc = {
    enable = lib.mkEnableOption "labwc";
    lock.enable = lib.mkEnableOption "labwc screen locking";
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
            example = "#00ffff";
            description = "Colour of the window frame";
          };
        };
      });
      default = [
        {
          identifier = "foot";
          colour = "#00ffff";
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

    environment.systemPackages = with pkgs;
      [labwc launchers]
      # Below sway packages needed for screen locking
      ++ lib.optionals config.ghaf.graphics.labwc.lock.enable [swaylock-effects swayidle]
      # Grim screenshot tool is used for labwc debug-builds
      ++ lib.optionals config.ghaf.profiles.debug.enable [grim];

    # It will create /etc/pam.d/swaylock file for authentication
    security.pam.services = lib.mkIf config.ghaf.graphics.labwc.lock.enable {swaylock = {};};

    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;
      "labwc/themerc".source = "${pkgs.labwc}/share/doc/labwc/themerc";
    };

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
        ExecStart = "${pkgs.labwc}/bin/labwc -C /etc/labwc -s ${autostart}/bin/labwc-autostart";
        #GPU pt needs some time to start - labwc fails to restart 3 times in avg.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        Restart = "on-failure";
        RestartSec = "1";

        # Ivan N: adding openssh into the PATH since it is needed for waypipe to work
        Environment = "PATH=${pkgs.openssh}/bin:$PATH";
      };
      environment = {
        WLR_RENDERER = "pixman";
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
  };
}
