# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.labwc;

  audio-ctrl = pkgs.callPackage ../../../packages/audio-ctrl { };
  ghaf-screenshot = pkgs.callPackage ../../../packages/ghaf-screenshot { };
  gtklockStyle = pkgs.callPackage ./styles/lock-style.nix { };
  lockCmd = "${pkgs.gtklock}/bin/gtklock -s ${gtklockStyle}";
  ghaf-launcher = pkgs.callPackage ./ghaf-launcher.nix { inherit config pkgs; };
  autostart = pkgs.writeShellApplication {
    name = "labwc-autostart";

    runtimeInputs = [
      pkgs.systemd
      pkgs.dbus
    ];

    text =
      ''
        # Import environment variables to ensure it is available to user
        # services
        systemctl --user import-environment WAYLAND_DISPLAY
        dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
        sleep 0.3 # make sure variables are set
        systemctl --user reset-failed
        systemctl --user stop ghaf-session.target
        systemctl --user start ghaf-session.target
      ''
      + cfg.extraAutostart;
  };
  rcXml = ''
    <?xml version="1.0"?>
    <labwc_config>
    <core><gap>5</gap></core>
    <theme>
      <name>Ghaf</name>
      <dropShadows>yes</dropShadows>
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
    <snapping>
      <overlay>
        <enabled>true</enabled>
        <delay inner="500" outer="500"/>
      </overlay>
    </snapping>
    <placement>
      <policy>cascade</policy>
      <cascadeOffset x="40" y="30" />
    </placement>
    <keyboard>
      <default />
      <keybind key="W-l">
        <action name="Execute" command="loginctl lock-session" />
      </keybind>
      ${lib.optionalString config.ghaf.profiles.debug.enable ''
        <keybind key="Print">
          <action name="Execute" command="${ghaf-screenshot}/bin/ghaf-screenshot" />
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
      <keybind key="W-z">
        <action name="ToggleMagnify" />
      </keybind>
      <keybind key="W--">
        <action name="ZoomOut" />
      </keybind>
      <keybind key="W-=">
        <action name="ZoomIn" />
      </keybind>
      <keybind key="Super_L" onRelease="yes">
        <action name="Execute" command="${pkgs.procps}/bin/pkill -USR1 nwg-drawer" />
      </keybind>
    </keyboard>
    <mouse>
      <default />
      <context name="Root">
        <mousebind button="Left" action="Press" />
        <mousebind button="Middle" action="Press" />
        ${
          lib.optionalString (!config.ghaf.profiles.debug.enable) ''
            <mousebind button="Right" action="Press" />
          ''
        }
      </context>
    </mouse>
    <windowRules>
      ${
        lib.concatStringsSep "\n" (
          map (rule: ''
            <windowRule identifier="${rule.identifier}" borderColor="${rule.colour}" serverDecoration="yes" skipTaskbar="no"  />
          '') cfg.frameColouring
        )
      }
      ${
        lib.concatStringsSep "\n" (
          map (rule: ''
            <windowRule sandboxAppId="${rule.identifier}" borderColor="${rule.color}" serverDecoration="yes" skipTaskbar="no"  />
          '') cfg.securityContext
        )
      }
    </windowRules>
    <libinput>
      <device category="touchpad"><naturalScroll>yes</naturalScroll></device>
    </libinput>
    <windowSwitcher show="yes" preview="yes" outlines="yes" allWorkspaces="yes">
      <fields>
        <field content="title"  width="75%" />
        <field content="output"  width="25%" />
      </fields>
    </windowSwitcher>
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
    background-color=#121212
    progress-color=source #3D8252e6
    border-radius=5
    border-size=0
    padding=10
    default-timeout=10000
  '';

  environment = ''
    XCURSOR_THEME=Adwaita
    XCURSOR_SIZE=24

    # Wayland compatibility
    MOZ_ENABLE_WAYLAND=1
  '';

  labwc-session = pkgs.writeShellApplication {
    name = "labwc-session";

    runtimeInputs = [
      pkgs.labwc
      autostart
    ];

    text = "labwc -C /etc/labwc -s labwc-autostart";
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;
      "labwc/environment".text = environment;

      "mako/config".text = makoConfig;

      "greetd/environments".text = lib.mkAfter "${labwc-session}/bin/labwc-session\n";
    };

    services.greetd.settings = {
      initial_session = lib.mkIf (cfg.autologinUser != null) {
        user = "ghaf";
        command = "${labwc-session}/bin/labwc-session";
      };
    };

    systemd.user.services = {
      ghaf-launcher = {
        enable = true;
        description = "Ghaf launcher daemon";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${ghaf-launcher}/bin/ghaf-launcher";
          Restart = "always";
          RestartSec = "1";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      swaybg = {
        enable = true;
        description = "Wallpaper daemon";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.swaybg}/bin/swaybg -m fill -i ${cfg.wallpaper}";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      mako = {
        enable = true;
        description = "Notification daemon";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.mako}/bin/mako -c /etc/mako/config";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      lock-event = {
        enable = true;
        description = "Lock Event Handler";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.swayidle}/bin/swayidle lock \"${lockCmd}\"";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      autolock = lib.mkIf cfg.autolock.enable {
        enable = true;
        description = "System autolock";
        serviceConfig = {
          Type = "simple";
          ExecStart = ''
            ${pkgs.swayidle}/bin/swayidle -w timeout ${builtins.toString cfg.autolock.duration} \
            # Start dimming for 3.5 seconds in the background
            '${pkgs.chayang}/bin/chayang -d 3.5 & CHAYANG_PID=$!; \
            sleep 3; \
            # If chayang is still running (i.e., user hasn't interrupted),
            # proceed with locking
            if kill -0 $CHAYANG_PID 2>/dev/null; then \
              loginctl lock-session; \
            fi'
          '';
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };
    };
  };
}
