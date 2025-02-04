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
  ghaf-powercontrol = pkgs.callPackage ../../../packages/ghaf-powercontrol {
    ghafConfig = config.ghaf;
  };
  ghaf-workspace = pkgs.callPackage ../../../packages/ghaf-workspace { };
  drawerStyle = pkgs.callPackage ./styles/launcher-style.nix { };
  inherit (config.ghaf.services.audio) pulseaudioTcpControlPort;
  gtklockStyle = pkgs.callPackage ./styles/lock-style.nix { };
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
        ${ghaf-workspace}/bin/ghaf-workspace max ${toString cfg.maxDesktops}

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
      <icon>${cfg.gtk.iconTheme}</icon>
      <dropShadows>yes</dropShadows>
      <titlebar>
        <layout>icon:iconify,max,close</layout>
      </titlebar>
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
    <desktops number="${toString cfg.maxDesktops}">
      <popupTime>0</popupTime>
    </desktops>
    <keyboard>
      <default />
      ${lib.concatStringsSep "\n" (
        builtins.map (index: ''
          <keybind key="W-${toString index}">
            <action name="GoToDesktop" to="${toString index}" />
            <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/workspace; ${ghaf-workspace}/bin/ghaf-workspace update ${toString index}'" />
          </keybind>
        '') (lib.lists.range 1 cfg.maxDesktops)
      )}
      <keybind key="W-A-Right">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/workspace; ${ghaf-workspace}/bin/ghaf-workspace next'" />
      </keybind>
      <keybind key="W-A-Left">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/workspace; ${ghaf-workspace}/bin/ghaf-workspace prev'" />
      </keybind>
      <keybind key="W-S-Right">
        <action name="SendToDesktop" to="right" follow="no" wrap="yes" />
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/workspace; ${ghaf-workspace}/bin/ghaf-workspace next'" />
      </keybind>
      <keybind key="W-S-Left">
        <action name="SendToDesktop" to="left" follow="no" wrap="yes" />
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/workspace; ${ghaf-workspace}/bin/ghaf-workspace prev'" />
      </keybind>
      <keybind key="W-l">
        <action name="Execute" command="${pkgs.systemd}/bin/loginctl lock-session" />
      </keybind>
      ${lib.optionalString config.ghaf.profiles.debug.enable ''
        <keybind key="Print">
          <action name="Execute" command="${ghaf-screenshot}/bin/ghaf-screenshot" />
        </keybind>
      ''}
      <keybind key="XF86_Display">
        <action name="Execute" command="${lib.getExe pkgs.wdisplays}" />
      </keybind>
      <keybind key="XF86_MonBrightnessUp">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/brightness; ${pkgs.brightnessctl}/bin/brightnessctl set +5%'" />
      </keybind>
      <keybind key="XF86_MonBrightnessDown">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/brightness; ${pkgs.brightnessctl}/bin/brightnessctl set 5%-'" />
      </keybind>
      <keybind key="XF86_AudioRaiseVolume">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/volume; ${pkgs.pamixer}/bin/pamixer --unmute --increase 5'" />
      </keybind>
      <keybind key="XF86_AudioLowerVolume">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/volume; ${pkgs.pamixer}/bin/pamixer --unmute --decrease 5'" />
      </keybind>
      <keybind key="XF86_AudioMute">
        <action name="Execute" command="bash -c 'echo 1 > ~/.config/eww/volume; ${pkgs.pamixer}/bin/pamixer --toggle-mute'" />
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
        ${lib.optionalString (!config.ghaf.profiles.debug.enable) ''
          <mousebind button="Right" action="Press" />
        ''}
      <!--Disable default scrolling behavior of switching workspaces-->
      <mousebind direction="Up" action="Scroll" />
      <mousebind direction="Down" action="Scroll" />
      </context>
    </mouse>
    <windowRules>
      ${lib.concatStringsSep "\n" (
        map (rule: ''
          <windowRule identifier="${rule.identifier}" borderColor="${rule.colour}" serverDecoration="yes" skipTaskbar="no"  />
        '') cfg.frameColouring
      )}
      ${lib.concatStringsSep "\n" (
        map (rule: ''
          <windowRule sandboxAppId="${rule.identifier}" borderColor="${rule.color}" serverDecoration="yes" skipTaskbar="no"  />
        '') cfg.securityContext
      )}
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
    on-button-left=invoke-default-action
    on-button-right=dismiss
    on-button-middle=dismiss
    on-touch=dismiss
    actions=1
    border-radius=5
    border-size=0
    padding=10
    icons=1
    icon-path=/run/current-system/sw/share/icons/${cfg.gtk.iconTheme}
    max-icon-size=32
    default-timeout=5000
    ignore-timeout=1

    [urgency=critical]
    ignore-timeout=0

    [app-name=blueman body~="(.*Authorization request.*)"]
    invisible=1
  '';

  gtklockConfig = ''
    [main]
    style=${gtklockStyle}
    layout=${pkgs.gtklock}/share/layout/gtklock.ui.xml
    date-format=%A, %b %d
    modules=${pkgs.gtklock-powerbar-module}/lib/gtklock/powerbar-module.so;${pkgs.gtklock-userinfo-module}/lib/gtklock/userinfo-module.so
    #background=
    idle-timeout=30
    idle-hide=true
    start-hidden=true
    #follow-focus=true
    #lock-command=
    #unlock-command=
    #monitor-priority=
    [userinfo]
    image-size=128
    under-clock=true
    [powerbar]
    #show-labels=true
    #linked-buttons=true
    reboot-command=${ghaf-powercontrol}/bin/ghaf-powercontrol reboot &
    poweroff-command=${ghaf-powercontrol}/bin/ghaf-powercontrol poweroff &
    suspend-command=${ghaf-powercontrol}/bin/ghaf-powercontrol suspend &
    logout-command=${pkgs.labwc}/bin/labwc --exit &
    #userswitch-command=
  '';

  swayidleConfig = ''
    timeout ${
      toString (builtins.floor (cfg.autolock.duration * 0.8))
    } 'notify-send -u critical -t 10000 -i system "Automatic suspend" "The system will suspend soon due to inactivity."; brightnessctl -q -s; brightnessctl -q -m | { IFS=',' read -r _ _ _ brightness _ && [ "''${brightness%\%}" -le 25 ] || brightnessctl -q set 25% ;}' resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${toString cfg.autolock.duration} "loginctl lock-session" resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${
      toString (builtins.floor (cfg.autolock.duration * 1.5))
    } "wlopm --off \*" resume "wlopm --on \*"
    timeout ${toString (builtins.floor (cfg.autolock.duration * 3))} "ghaf-powercontrol suspend"
    after-resume "wlopm --on \*; brightnessctl -q -r || brightnessctl -q set 100%"
    unlock "brightnessctl -q -r || brightnessctl -q set 100%"
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

  auto-display-scale = pkgs.writeShellApplication {
    name = "auto-display-scale";
    runtimeInputs = [
      pkgs.wlr-randr
      pkgs.jq
      pkgs.gawk
      pkgs.bc
      pkgs.systemd
    ];
    bashOptions = [ ];
    text = ''
      start() {
        wlr-randr --json | jq -c --unbuffered '.[] | select(.enabled == true)' | while read -r display; do
          # Extract necessary details from JSON
          name=$(echo "$display" | jq -r '.name')
          width_mm=$(echo "$display" | jq -r '.physical_size.width')
          height_mm=$(echo "$display" | jq -r '.physical_size.height')
          mode=$(echo "$display" | jq -c '.modes[] | select(.current == true)')
          width_px=$(echo "$mode" | jq -r '.width')
          height_px=$(echo "$mode" | jq -r '.height')

          pos_x=$(echo "$display" | jq -r '.position.x')
          pos_y=$(echo "$display" | jq -r '.position.y')
          scale=$(echo "$display" | jq -r '.scale')

          # Validate extracted values
          if [[ -z "$name" || -z "$width_mm" || -z "$height_mm" || -z "$width_px" || -z "$height_px" || -z "$pos_x" || -z "$pos_y" ]]; then
              echo "Error: Missing data for display $name. Skipping."
              continue
          elif [[ "$(echo "$scale != 1" | bc -l)" -eq 1 ]]; then
              # Don't adjust scaling if custom scaling is already set
              continue
          fi

          # Convert physical dimensions to inches
          width_in=$(echo "$width_mm" | awk '{print $1 / 25.4}')
          height_in=$(echo "$height_mm" | awk '{print $1 / 25.4}')

          diagonal_px=$(echo "$width_px $height_px" | awk '{print sqrt($1^2 + $2^2)}')
          diagonal_in=$(echo "$width_in $height_in" | awk '{print sqrt($1^2 + $2^2)}')
          ppi=$(echo "$diagonal_px $diagonal_in" | awk '{print $1 / $2}')

          # Check if the display is a TV size
          is_tv=$(echo "$diagonal_in >= 40" | bc -l) # Consider displays with a diagonal >= 40 inches as TVs
          if [[ "$is_tv" -eq 1 ]]; then
              if (( $(echo "$diagonal_in <= 65" | bc -l) )); then
                  calculated_scale=1.50 # Apply 150% scaling for TVs 65 inches and under
              else
                  calculated_scale=1.75 # Apply 175% scaling for TVs larger than 65 inches
              fi
          else
              # Determine scaling factor based on PPI
              if (( $(echo "$ppi >= 0 && $ppi < 170" | bc -l) )); then
                  calculated_scale=1        # No scaling for PPI lower than 170
              elif (( $(echo "$ppi >= 170 && $ppi < 200" | bc -l) )); then
                  calculated_scale=1.25     # 125% scaling for PPI between 170 and 200
              elif (( $(echo "$ppi >= 200 && $ppi < 300" | bc -l) )); then
                  calculated_scale=1.50     # 150% scaling for PPI between 200 and 300
              else
                  calculated_scale=2        # 200% scaling for PPI above 300
              fi
          fi

          # Apply scaling using wlr-randr
          wlr-randr --output "$name" --preferred --scale "$calculated_scale" --pos "$pos_x,$pos_y" && \
            echo "Applied settings for display $name: Scale=$calculated_scale, Position=($pos_x, $pos_y), Size=$diagonal_in inches, PPI=$ppi."
        done
      }

      reset() {
        wlr-randr --json | jq -c --unbuffered '.[] | select(.enabled == true)' | while read -r display; do
          name=$(echo "$display" | jq -r '.name')
          echo "Display $name: Resetting scaling"
          wlr-randr --output "$name" --preferred --scale 1 && echo "Display $name scaling reset to 1"
        done
        echo "Done resetting display scaling"
        systemctl --user reload ewwbar && echo "Ewwbar reloaded"
      }

      case "$1" in
        reset)
            reset
            ;;
        *)
            start
            ;;
      esac
    '';
  };

  display-event-trigger = pkgs.writeShellApplication {
    name = "display-event-trigger";
    runtimeInputs = [ ];
    bashOptions = [ ];
    text = ''
      # Run the following commands in order every time a display change event is detected
      ${auto-display-scale}/bin/auto-display-scale        # Auto scaling
      ${pkgs.mako}/bin/makoctl set-mode default   # Reset mako mode so notifications don't break
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "labwc/rc.xml".text = rcXml;
      "labwc/menu.xml".text = menuXml;
      "labwc/environment".text = environment;

      "gtklock/config.ini".text = gtklockConfig;

      "swayidle/config".text = swayidleConfig;

      "mako/config".text = makoConfig;

      "greetd/environments".text = lib.mkAfter "ghaf-session\n";
    };

    environment.systemPackages = [ ghaf-session ];

    services.greetd.settings = {
      initial_session = lib.mkIf (cfg.autologinUser != null) {
        user = config.ghaf.users.admin.name;
        command = "ghaf-session";
      };
    };

    services.udev.extraRules = ''
      ACTION=="change", SUBSYSTEM=="drm", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="display-change-trigger.service"
    '';

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
          ExecStart = "${pkgs.swayidle}/bin/swayidle lock \"${pkgs.gtklock}/bin/gtklock -c /etc/gtklock/config.ini\"";
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
          Environment = "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock";
          ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
        };
        wantedBy = [ "ewwbar.service" ];
        after = [ "ewwbar.service" ];
        partOf = [ "ewwbar.service" ];
      };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        enable = true;
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = [
            ""
            "${pkgs.bt-launcher}/bin/bt-launcher applet"
          ];
        };
        wantedBy = [ "ewwbar.service" ];
        after = [ "ewwbar.service" ];
        partOf = [ "ewwbar.service" ];
      };

      blueman-manager = {
        serviceConfig.ExecStart = [
          ""
          "${pkgs.bt-launcher}/bin/bt-launcher"
        ];
      };

      swayidle = lib.mkIf cfg.autolock.enable {
        enable = true;
        description = "System idle handler";
        path = [
          pkgs.brightnessctl
          pkgs.systemd
          pkgs.wlopm
          ghaf-powercontrol
          pkgs.libnotify
        ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.swayidle}/bin/swayidle -w -C /etc/swayidle/config";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      hidpi-auto-scaling = {
        description = "HiDPI scaling service at boot";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${auto-display-scale}/bin/auto-display-scale";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
        before = [
          "ewwbar.service"
          "swaybg.service"
        ];
      };

      hidpi-auto-scaling-reset = {
        description = "Reset HiDPI auto scaling performed at boot";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${auto-display-scale}/bin/auto-display-scale reset";
        };
      };

      display-change-trigger = {
        description = "display-change-trigger";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${display-event-trigger}/bin/display-event-trigger";
        };
      };
    };
  };
}
