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

  ghaf-screenshot = pkgs.callPackage ../../../packages/ghaf-screenshot { };
  ghaf-workspace = pkgs.callPackage ../../../packages/ghaf-workspace { };
  drawerStyle = pkgs.callPackage ./styles/launcher-style.nix { };
  inherit (config.ghaf.services.audio) pulseaudioTcpControlPort;
  gtklockStyle = pkgs.callPackage ./styles/lock-style.nix { };
  lockCmd = "${pkgs.gtklock}/bin/gtklock -s ${gtklockStyle}";
  autostart = pkgs.writeShellApplication {
    name = "labwc-autostart";

    runtimeInputs = [
      pkgs.systemd
      pkgs.dbus
      pkgs.glib
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

        # Get the current workspace
        current_workspace=$(${ghaf-workspace}/bin/ghaf-workspace cur 2>/dev/null)

        # Check if the current workspace is a valid number
        if ! [ "$current_workspace" -ge 1 ] 2>/dev/null; then
            echo "Invalid workspace detected. Switching to workspace 1..."
            ${ghaf-workspace}/bin/ghaf-workspace switch 1
        else
            ${ghaf-workspace}/bin/ghaf-workspace switch "$current_workspace"
        fi
        ${ghaf-workspace}/bin/ghaf-workspace max 2

        # Write the GTK settings to the settings.ini file in the GTK config directory
        # Note:
        # - On Wayland, GTK+ is known for not picking themes from settings.ini.
        # - We define GTK+ theme on Wayland using gsettings (e.g., `gsettings set org.gnome.desktop.interface ...`).
        mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"
        echo -e "${gtk_settings}" > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"

        gnome_schema="org.gnome.desktop.interface"

        gsettings set "$gnome_schema" gtk-theme "${cfg.gtk.theme}"
        gsettings set "$gnome_schema" icon-theme "${cfg.gtk.iconTheme}"
        gsettings set "$gnome_schema" font-name "${cfg.gtk.fontName} ${cfg.gtk.fontSize}"
        gsettings set "$gnome_schema" color-scheme "${cfg.gtk.colorScheme}"
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
        <name>${cfg.gtk.fontName}</name>
        <size>12</size>
        <slant>normal</slant>
        <weight>bold</weight>
      </font>
      <font place="ActiveWindow">
        <name>${cfg.gtk.fontName}</name>
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
    <desktops number="2">
      <popupTime>0</popupTime>
    </desktops>
    <keyboard>
      <default />
      <keybind key="W-1"><action name="GoToDesktop" to="1" />
        <action name="Execute" command="${ghaf-workspace}/bin/ghaf-workspace update 1" />
      </keybind>
      <keybind key="W-2"><action name="GoToDesktop" to="2" />
        <action name="Execute" command="${ghaf-workspace}/bin/ghaf-workspace update 2" />
      </keybind>
      <keybind key="W-A-Right">
        <action name="Execute" command="${ghaf-workspace}/bin/ghaf-workspace next" />
      </keybind>
      <keybind key="W-A-Left">
        <action name="Execute" command="${ghaf-workspace}/bin/ghaf-workspace prev" />
      </keybind>
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
        <action name="Execute" command="${pkgs.pamixer}/bin/pamixer --unmute --increase 5" />
      </keybind>
      <keybind key="XF86_AudioLowerVolume">
        <action name="Execute" command="${pkgs.pamixer}/bin/pamixer --unmute --decrease 5" />
      </keybind>
      <keybind key="XF86_AudioMute">
        <action name="Execute" command="${pkgs.pamixer}/bin/pamixer --toggle-mute" />
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
      <!--Disable default scrolling behavior of switching workspaces-->
      <mousebind direction="Up" action="Scroll" />
      <mousebind direction="Down" action="Scroll" />
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
    font=${cfg.gtk.fontName} ${cfg.gtk.fontSize}
    background-color=#121212
    progress-color=source #3D8252e6
    border-radius=5
    border-size=0
    padding=10
    icons=1
    icon-path=/run/current-system/sw/share/icons/${cfg.gtk.iconTheme}
    max-icon-size=32
    default-timeout=5000
    ignore-timeout=1

    [app-name=blueman body~="(.*Authorization request.*)"]
    invisible=1
  '';

  environment = ''
    XCURSOR_THEME=Adwaita
    XCURSOR_SIZE=24
    PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort}

    # Wayland compatibility
    MOZ_ENABLE_WAYLAND=1
  '';

  gtk_settings = ''
    [Settings]
    ${
      if cfg.gtk.colorScheme == "prefer-dark" then
        "gtk-application-prefer-dark-theme = true"
      else
        "gtk-application-prefer-dark-theme = false"
    }
  '';

  ghaf-session = pkgs.writeShellApplication {
    name = "ghaf-session";

    runtimeInputs = [
      pkgs.labwc
      autostart
    ];

    text = "labwc -C /etc/labwc -s labwc-autostart >/tmp/session.labwc.log 2>&1";
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;
      "labwc/environment".text = environment;

      "mako/config".text = makoConfig;

      "greetd/environments".text = lib.mkAfter "ghaf-session\n";
    };

    environment.systemPackages = [ ghaf-session ];

    services.greetd.settings = {
      initial_session = lib.mkIf (cfg.autologinUser != null) {
        user = "ghaf";
        command = "ghaf-session";
      };
    };

    systemd.user.services = {
      ghaf-launcher = {
        enable = true;
        description = "Ghaf launcher daemon";
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = "-/etc/locale.conf";
          ExecStart = "${pkgs.nwg-drawer}/bin/nwg-drawer -r -nofs -nocats -s ${drawerStyle}";
          Restart = "always";
          RestartSec = "1";
        };
        startLimitIntervalSec = 0;
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

      nm-applet = {
        enable = true;
        description = "network manager graphical interface.";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${pkgs.nm-launcher}/bin/nm-launcher";
        };
        wantedBy = [ "ghaf-session.target" ];
        partOf = [ "ghaf-session.target" ];
      };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        enable = true;
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          Environment = "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/bt_applet_ssh_system_dbus.sock";
          ExecStart = [
            ""
            "${pkgs.bt-launcher}/bin/bt-launcher applet"
          ];
        };
        wantedBy = [ "ghaf-session.target" ];
        partOf = [ "ghaf-session.target" ];
        after = [ "ewwbar.service" ];
      };

      blueman-manager = {
        serviceConfig.ExecStart = [
          ""
          "${pkgs.bt-launcher}/bin/bt-launcher"
        ];
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
        after = [ "ewwbar.service" ];
      };
    };
  };
}
