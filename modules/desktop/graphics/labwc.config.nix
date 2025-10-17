# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.labwc;
  inherit (pkgs) ghaf-workspace ghaf-screenshot;
  inherit (config.ghaf.services.audio) pulseaudioTcpControlPort;
  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };
  drawerStyle = pkgs.callPackage ./styles/launcher-style.nix { };
  gtklockStyle = pkgs.callPackage ./styles/lock-style.nix { };

  autostart = pkgs.writeShellApplication {
    name = "labwc-autostart";

    runtimeInputs = [
      pkgs.systemd
      pkgs.dbus
      pkgs.glib
    ];

    text = ''
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
      mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
      [ ! -f "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ] && echo -ne "${gtk-settings}" > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
      [ ! -f "$XDG_CONFIG_HOME/gtk-4.0/settings.ini" ] && echo -ne "${gtk-settings}" > "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
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
      <prefix>Desktop</prefix>
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
    logout-command=
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

  ghaf-session = pkgs.writeShellApplication {
    name = "ghaf-session";

    runtimeInputs = [
      pkgs.labwc
      autostart
    ];

    text = "labwc -C /etc/labwc -s labwc-autostart >/tmp/session.labwc.log 2>&1";
  };

  gtk-settings = ''
    [Settings]
    ${
      if cfg.gtk.colorScheme == "prefer-dark" then
        "gtk-application-prefer-dark-theme=1"
      else
        "gtk-application-prefer-dark-theme=0"
    }
    gtk-theme-name=${cfg.gtk.theme}
    gtk-icon-theme-name=${cfg.gtk.iconTheme}
    gtk-font-name=${cfg.gtk.fontName} ${cfg.gtk.fontSize}
    gtk-enable-event-sounds=1
    gtk-enable-input-feedback-sounds=1
    gtk-xft-antialias=1
    gtk-xft-hinting=1
    gtk-xft-hintstyle=hintslight
    gtk-xft-rgba=rgb
  '';

  ghaf-display = pkgs.writeShellApplication {
    name = "ghaf-display";
    runtimeInputs = [
      pkgs.wlr-randr
      pkgs.jq
      pkgs.gawk
      pkgs.bc
      pkgs.systemd
    ];
    bashOptions = [ ];
    text = ''
      TMP_CONFIG=
      WLR_RANDR_CONFIG=
      CONFIG="$HOME/.config/display/config"

      auto-scale() {
        wlr-randr --json | jq -c --unbuffered '.[] | select(.enabled == true)' | while read -r display; do
          # Extract necessary details from JSON
          name=$(echo "$display" | jq -r '.name')
          current_scale=$(echo "$display" | jq -r '.scale')

          if (( $(echo "$current_scale != 1" | bc -l) )); then
              echo "Skipping $name: Scaling is already set to $current_scale"
              continue
          fi

          width_mm=$(echo "$display" | jq -r '.physical_size.width')
          height_mm=$(echo "$display" | jq -r '.physical_size.height')
          mode=$(echo "$display" | jq -c '.modes[] | select(.current == true)')
          width_px=$(echo "$mode" | jq -r '.width')
          height_px=$(echo "$mode" | jq -r '.height')

          pos_x=$(echo "$display" | jq -r '.position.x')
          pos_y=$(echo "$display" | jq -r '.position.y')

          # Validate extracted values
          if [[ -z "$name" || -z "$width_mm" || -z "$height_mm" || -z "$width_px" || -z "$height_px" || -z "$pos_x" || -z "$pos_y" ||
                "$width_mm" -eq 0 || "$height_mm" -eq 0 || "$width_px" -eq 0 || "$height_px" -eq 0 ]]; then
              echo "Error: Missing or zero data for display $name. Skipping."
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
          is_4k=$(echo "$width_px >= 3840 && $height_px >= 2160" | bc -l)
          echo "Display detected: is_tv=$is_tv, is_4k=$is_4k, diagonal_in=$diagonal_in, resolution=''${width_px}x''${height_px}"
          if [[ "$is_tv" -eq 1 && "$is_4k" -eq 1 ]]; then
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
          wlr-randr --output "$name" --scale "$calculated_scale" --pos "$pos_x,$pos_y" && \
            echo "Applied settings for display $name: Scale=$calculated_scale, Position=($pos_x, $pos_y), Size=$diagonal_in inches, PPI=$ppi."
        done
      }

      reset-scale() {
        wlr-randr --json | jq -c --unbuffered '.[] | select(.enabled == true)' | while read -r display; do
          name=$(echo "$display" | jq -r '.name')
          echo "Display $name: Resetting scaling"
          wlr-randr --output "$name" --preferred --scale 1 && echo "Display $name scaling reset to 1"
        done
        echo "Done resetting display scaling"
        systemctl --user reload ewwbar && echo "Ewwbar reloaded"
      }

      # Generate a simple config that can be executed directly by wlr-randr
      generate-config() {
          [[ -z "$WLR_RANDR_CONFIG" ]] && WLR_RANDR_CONFIG=$(wlr-randr)

          echo "$WLR_RANDR_CONFIG" | awk '
              /^[^ ]/ {output=$1}
              /Position:/ { pos=$2 }
              /Enabled:/ {
                  enabled = ($2 == "yes" ? "--on" : "--off");
                  if (enabled == "--off") {
                      print "--output " output " " enabled;
                      next
                  }
              }
              /Transform:/ { transform=$2 }
              /Scale:/ {scale=$2; print "--output " output " " enabled " --pos " pos " --scale " scale " --transform " transform}
          ' > "$CONFIG"
      }

      check-for-changes() {
          WLR_RANDR_CONFIG=$(wlr-randr)

          if [ "$WLR_RANDR_CONFIG" != "$TMP_CONFIG" ]; then
              TMP_CONFIG="$WLR_RANDR_CONFIG"
              return 0
          fi
          return 1
      }

      apply-config() {
          # Ensure the config file exists
          if [ ! -f "$CONFIG" ]; then
              echo "Config file not found: $CONFIG"
              exit 1
          fi

          # Read and apply each line as a wlr-randr command
          while IFS= read -r line; do
              if [[ -n "$line" ]]; then
                  echo "Applying display config: wlr-randr $line"
                  eval "wlr-randr $line" || echo "Warning: config '$line' could not be applied"
              fi
          done < "$CONFIG"
      }

      case "$1" in
        reset-scale)
            reset-scale
            ;;
        auto-scale)
            auto-scale
            ;;
        apply-config)
            apply-config
            ;;
        generate-config)
            generate-config
            ;;
        monitor)
            mkdir -p ~/.config/display && touch "$CONFIG"
            CMD=''${2:-"systemctl --user reload ewwbar"}  # Command to execute
            SLEEP_DURATION=''${3:-1}  # Sleep duration

            while true; do
                if check-for-changes; then
                    eval "$CMD"
                fi
                sleep "$SLEEP_DURATION"
            done
            ;;
        boot-setup)
            apply-config || true
            auto-scale
            ;;
        *)
            echo "Unknown command"
            echo
            echo "Commands:"
            echo "  reset-scale                           - Resets all displays to their default scale (100%)."
            echo "  auto-scale                            - Automatically adjusts scaling based on display size and resolution."
            echo "  apply-config                          - Applies the saved display configuration from $CONFIG."
            echo "  generate-config                       - Generates a new display configuration at $CONFIG."
            echo "  monitor [command] [polling_interval]  - Continuously monitors for display changes every [polling_interval] by and runs [command]."
            echo "  boot-setup                            - Applies saved display config and performs automatic scaling."
            exit 1
      esac
    '';
  };

  display-event-trigger = pkgs.writeShellApplication {
    name = "display-event-trigger";
    runtimeInputs = [
      ghaf-display
      pkgs.mako
      pkgs.wlr-randr
      pkgs.jq
    ];
    bashOptions = [ ];
    text = ''
      stop_services() {
        echo "Stopping ghaf-launcher and ewwbar services."
        systemctl --user stop ewwbar ghaf-launcher
      }

      ghaf-display auto-scale   # Auto scaling
      makoctl set-mode default  # Reset mako mode so notifications don't break

      # Retrieve display information
      if ! wlr_output_json=$(wlr-randr --json); then
        echo "Error: Failed to get display info from wlr-randr"
        stop_services
      fi

      # Check if any displays are connected
      if ! echo "$wlr_output_json" | jq -e 'length > 0' > /dev/null; then
        echo "Error: No connected displays found."
        stop_services
      fi

      # If displays are connected (not headless mode), ensure ewwbar and ghaf-launcher are running
      systemctl --user is-active --quiet ewwbar || systemctl --user reload-or-restart ewwbar
      systemctl --user is-active --quiet ghaf-launcher || systemctl --user reload-or-restart ghaf-launcher
    '';
  };

  display-connected = pkgs.writeShellApplication {
    name = "display-connected";
    runtimeInputs = [
      pkgs.jq
      pkgs.wlr-randr
    ];
    bashOptions = [ ];
    text = ''
      # Exits with error if no display is detected

      # Retrieve display information
      if ! wlr_output_json=$(wlr-randr --json); then
        echo "Error: Failed to get display info from wlr-randr"
        exit 1
      fi

      # Check if any displays are connected
      if ! echo "$wlr_output_json" | jq -e 'length > 0' > /dev/null; then
        echo "Error: No connected displays found."
        exit 1
      fi
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

    programs.dconf = {
      enable = true;
      profiles.user = {
        databases = [
          {
            lockAll = false;
            settings = {
              "org/gnome/desktop/interface" = {
                color-scheme = cfg.gtk.colorScheme;
                gtk-theme = cfg.gtk.theme;
                icon-theme = cfg.gtk.iconTheme;
                font-name = "${cfg.gtk.fontName} ${cfg.gtk.fontSize}";
                clock-format = "24h";
              };
            };
          }
        ];
      };
    };

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
          ExecCondition = "${display-connected}/bin/display-connected";
          ExecStart = ''
            ${lib.getExe pkgs.bash} -c "PATH=/run/current-system/sw/bin:$PATH ${lib.getExe pkgs.nwg-drawer} -r -nofs -nocats -s ${drawerStyle}"
          '';
          Restart = "always";
          RestartSec = "1";
        };
        environment = cfg.extraVariables;
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
          ExecCondition = "${display-connected}/bin/display-connected";
          ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
        };
        wantedBy = [ "ewwbar.service" ];
        after = [ "ewwbar.service" ];
        partOf = [ "ewwbar.service" ];
      };

      audio-control = {
        enable = true;
        description = "Audio Control application";

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5";
          ExecCondition = "${display-connected}/bin/display-connected";
          ExecStart = "${pkgs.ghaf-audio-control}/bin/GhafAudioControlStandalone --pulseaudio_server=audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort} --deamon_mode=true --indicator_icon_name=audio-subwoofer";
        };

        partOf = [ "ewwbar.service" ];
        after = [ "ewwbar.service" ];
        wantedBy = [ "ewwbar.service" ];
      };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        enable = true;
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          Environment = "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock";
        };
        wantedBy = [ "ewwbar.service" ];
        after = [ "ewwbar.service" ];
        partOf = [ "ewwbar.service" ];
      };

      blueman-manager = {
        enable = true;
        serviceConfig = {
          Environment = "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock";
        };
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
        description = "Automatic scaling";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${ghaf-display}/bin/ghaf-display boot-setup";
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
          ExecStart = "${ghaf-display}/bin/ghaf-display reset-scale";
        };
      };

      display-change-trigger = {
        description = "display-change-trigger";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${display-event-trigger}/bin/display-event-trigger";
        };
      };

      display-config-monitor = {
        # Check for display changes every 60s and generate display config
        description = "Display config monitor";
        serviceConfig = {
          ExecStart = "${ghaf-display}/bin/ghaf-display monitor \"${ghaf-display}/bin/ghaf-display generate-config\" 60";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
        before = [ "ewwbar.service" ];
        after = [ "hidpi-auto-scaling.service" ];
      };

      ewwbar-reload-monitor = {
        # Check for display changes every 1s and reload ewwbar
        description = "Ewwbar reload monitor";
        serviceConfig = {
          ExecStart = "${ghaf-display}/bin/ghaf-display monitor \"systemctl --user reload ewwbar\" 1";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
        after = [
          "hidpi-auto-scaling.service"
          "ewwbar.service"
        ];
      };
    };
  };
}
