# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  makoConfig = ''
    font=Inter 12
    background-color=#202020e6
    progress-color=source #3D8252e6
    border-radius=5
    border-size=0
    padding=10
    default-timeout=10000
  '';
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
      ${pkgs.mako}/bin/mako -c /etc/mako/config >/dev/null 2>&1 &

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
    <core><gap>5</gap></core>
    <theme>
      <font place="">
        <name>Inter</name>
        <size>10</size>
        <slant>normal</slant>
        <weight>normal</weight>
      </font>
      <font place="ActiveWindow">
        <name>Inter</name>
        <size>12</size>
        <slant>normal</slant>
        <weight>bold</weight>
      </font>
    </theme>
    <keyboard>
      <default />
      ${lib.optionalString config.ghaf.profiles.debug.enable ''
      <keybind key="Print">
        <action name="Execute" command="${pkgs.grim}/bin/grim" />
      </keybind>
    ''}
      <keybind key="XF86_MonBrightnessUp">
        <action name="Execute" command="${pkgs.brightnessctl}/bin/brightnessctl set +10%" />
      </keybind>
      <keybind key="XF86_MonBrightnessDown">
        <action name="Execute" command="${pkgs.brightnessctl}/bin/brightnessctl set 10%-" />
      </keybind>
    </keyboard>
    <mouse><default /></mouse>
    <windowRules>
      ${lib.concatStringsSep "\n" (map (rule: ''
        <windowRule identifier="${rule.identifier}" borderColor="${rule.colour}" serverDecoration="yes" skipTaskbar="no"  />
      '')
      cfg.frameColouring)}
    </windowRules>
    <libinput>
      <device category="default"><naturalScroll>yes</naturalScroll></device>
    </libinput>
    </labwc_config>
  '';

  themeRc = ''
    # general
    border.width: 3
    padding.height: 6

    # The following options has no default, but fallbacks back to
    # font-height + 2x padding.height if not set.
    # titlebar.height:

    # window border
    window.active.border.color: #1d1d1d
    window.inactive.border.color: #353535

    # ToggleKeybinds status indicator
    window.active.indicator.toggled-keybind.color: #f15025

    # window titlebar background
    window.active.title.bg.color: #1d1d1d
    window.inactive.title.bg.color: #353535

    # window titlebar text
    window.active.label.text.color: #ffffff
    window.inactive.label.text.color: #bbbbbb
    window.label.text.justify: center

    # window buttons
    window.active.button.unpressed.image.color: #ffffff
    window.inactive.button.unpressed.image.color: #ffffff

    # Note that "menu", "iconify", "max", "close" buttons colors can be defined
    # individually by inserting the type after the button node, for example:
    #
    #     window.active.button.iconify.unpressed.image.color: #333333

    # menu
    menu.overlap.x: 0
    menu.overlap.y: 0
    menu.width.min: 20
    menu.width.max: 200
    menu.items.bg.color: #353535
    menu.items.text.color: #ffffff
    menu.items.active.bg.color: #1d1d1d
    menu.items.active.text.color: #ffffff
    menu.items.padding.x: 7
    menu.items.padding.y: 4
    menu.separator.width: 1
    menu.separator.padding.width: 6
    menu.separator.padding.height: 3
    menu.separator.color: #2b2b2b

    # on screen display (window-cycle dialog)
    osd.bg.color: #1d1d1d
    osd.border.color: #ffffff
    osd.border.width: 1
    osd.label.text.color: #ffffff

    osd.window-switcher.width: 600
    osd.window-switcher.padding: 4
    osd.window-switcher.item.padding.x: 10
    osd.window-switcher.item.padding.y: 1
    osd.window-switcher.item.active.border.width: 2

    osd.workspace-switcher.boxes.width: 20
    osd.workspace-switcher.boxes.height: 20
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
        <item label="Always On Top">
          <action name="ToggleAlwaysOnTop" />
        </item>
      </menu>
      <menu id="root-menu">
        <!-- We need some entry here, otherwise labwc will populate
        'Reconfigure' and 'Exit' items -->
        <item label="Ghaf Platform"></item>
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
      [pkgs.labwc launchers]
      # Below sway packages needed for screen locking
      ++ lib.optionals config.ghaf.graphics.labwc.lock.enable [pkgs.swaylock-effects pkgs.swayidle]
      # Grim screenshot tool is used for labwc debug-builds
      ++ lib.optionals config.ghaf.profiles.debug.enable [pkgs.grim];

    # It will create /etc/pam.d/swaylock file for authentication
    security.pam.services = lib.mkIf config.ghaf.graphics.labwc.lock.enable {swaylock = {};};

    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;
      "labwc/themerc-override".text = themeRc;

      "mako/config".text = makoConfig;
    };

    fonts.fontconfig.defaultFonts.sansSerif = ["Inter"];

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
        # ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
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

    #Allow video group to change brightness
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video $sys$devpath/brightness", RUN+="${pkgs.coreutils}/bin/chmod a+w $sys$devpath/brightness"
    '';
  };
}
