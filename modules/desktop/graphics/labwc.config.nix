# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;

  audio-ctrl = pkgs.callPackage ../../../packages/audio-ctrl {};
  gtklockStyle = pkgs.writeText "gtklock.css" ''
    window {
      background: rgba(29, 29, 29, 1);
      color: #eee;
    }
    button {
      box-shadow: none;
      border-radius: 5px;
      border: 1px solid rgba(255, 255, 255, 0.09);
      background: rgba(255, 255, 255, 0.06);
    }
    entry {
      background-color: rgba (43, 43, 43, 1);
      border: 1px solid rgba(46, 46, 46, 1);
      color: #eee;
    }
    entry:focus {
      box-shadow: none;
      border: 1px solid rgba(223, 92, 55, 1);
    }
  '';
  lockCmd = "${pkgs.gtklock}/bin/gtklock -s ${gtklockStyle}";
  autostart = pkgs.writeShellApplication {
    name = "labwc-autostart";

    runtimeInputs =
      [
        pkgs.systemd
        pkgs.swaybg
        pkgs.kanshi
        pkgs.waybar
        pkgs.mako

        (pkgs.callPackage ./ghaf-launcher.nix {inherit config pkgs;})
      ]
      ++ lib.optionals cfg.autolock.enable [
        pkgs.swayidle
        pkgs.chayang
      ];

    text =
      ''
        # Import WAYLAND_DISPLAY variable to make it available to waypipe and other systemd services
        systemctl --user import-environment WAYLAND_DISPLAY 2>&1 &

        # Launch the task bar
        waybar -s /etc/waybar/style.css -c /etc/waybar/config >/dev/null 2>&1 &

        # Set the wallpaper.
        swaybg -m fill -i ${cfg.wallpaper} >/dev/null 2>&1 &

        # Configure output directives such as mode, position, scale and transform.
        kanshi >/dev/null 2>&1 &

        # Enable notifications.
        mako -c /etc/mako/config >/dev/null 2>&1 &

        ${lib.optionalString cfg.autolock.enable ''
          swayidle -w timeout ${builtins.toString cfg.autolock.duration} \
          'chayang && ${lockCmd}' &
        ''}
      ''
      + cfg.extraAutostart;
  };
  rcXml = ''
    <?xml version="1.0"?>
    <labwc_config>
    <core><gap>5</gap></core>
    <theme>
      <name>Ghaf</name>
      <font place="">
        <name>Inter</name>
        <size>12</size>
        <slant>normal</slant>
        <weight>bold</weight>
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
      <keybind key="W-l">
        <action name="Execute" command="${lockCmd}" />
      </keybind>
      ${lib.optionalString config.ghaf.profiles.debug.enable ''
      <keybind key="Print">
        <action name="Execute" command="${pkgs.grim}/bin/grim" />
      </keybind>
    ''}
      <keybind key="XF86_MonBrightnessUp">
        <action name="Execute" command="${pkgs.brightnessctl}/bin/brightnessctl set +5%" />
      </keybind>
      <keybind key="XF86_MonBrightnessDown">
        <action name="Execute" command="${pkgs.brightnessctl}/bin/brightnessctl set 5%-" />
      </keybind>
      <keybind key="XF86_AudioRaiseVolume">
        <action name="Execute" command="${audio-ctrl}/bin/audio-ctrl inc" />
      </keybind>
      <keybind key="XF86_AudioLowerVolume">
        <action name="Execute" command="${audio-ctrl}/bin/audio-ctrl dec" />
      </keybind>
      <keybind key="XF86_AudioMute">
        <action name="Execute" command="${audio-ctrl}/bin/audio-ctrl mut" />
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
        ${lib.optionalString config.ghaf.profiles.debug.enable ''
      <item label="Terminal">
        <action name="Execute" command="${pkgs.foot}/bin/foot" />
      </item>
    ''}
      </menu>
    </openbox_menu>
  '';

  makoConfig = ''
    font=Inter 12
    background-color=#202020e6
    progress-color=source #3D8252e6
    border-radius=5
    border-size=0
    padding=10
    default-timeout=10000
  '';
in {
  config = lib.mkIf cfg.enable {
    systemd.user.services."labwc".serviceConfig = {
      ExecStart = "${pkgs.labwc}/bin/labwc -C /etc/labwc -s ${autostart}/bin/labwc-autostart";
    };

    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;

      "mako/config".text = makoConfig;
    };

    ghaf.graphics.launchers = [
      {
        name = "Lock";
        path = "${lockCmd}";
        icon = "${pkgs.icon-pack}/system-lock-screen.svg";
      }
    ];
  };
}
