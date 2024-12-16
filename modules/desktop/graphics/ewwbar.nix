# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib) optionalString;

  cfg = config.ghaf.graphics.labwc;
  useGivc = config.ghaf.givc.enable;
  ghaf-workspace = pkgs.callPackage ../../../packages/ghaf-workspace { };
  ghaf-powercontrol = pkgs.callPackage ../../../packages/ghaf-powercontrol {
    ghafConfig = config.ghaf;
  };
  inherit (config.ghaf.services.audio) pulseaudioTcpControlPort;

  launcher-icon = "${pkgs.ghaf-artwork}/icons/launcher.svg";

  battery-0-icon = "${pkgs.ghaf-artwork}/icons/battery-0.svg";
  battery-1-icon = "${pkgs.ghaf-artwork}/icons/battery-1.svg";
  battery-2-icon = "${pkgs.ghaf-artwork}/icons/battery-2.svg";
  battery-3-icon = "${pkgs.ghaf-artwork}/icons/battery-3.svg";
  battery-charging-icon = "${pkgs.ghaf-artwork}/icons/battery-charging.svg";

  volume-0-icon = "${pkgs.ghaf-artwork}/icons/volume-0.svg";
  volume-1-icon = "${pkgs.ghaf-artwork}/icons/volume-1.svg";
  volume-2-icon = "${pkgs.ghaf-artwork}/icons/volume-2.svg";
  volume-3-icon = "${pkgs.ghaf-artwork}/icons/volume-3.svg";

  brightness-0-icon = "${pkgs.ghaf-artwork}/icons/brightness-0.svg";
  brightness-1-icon = "${pkgs.ghaf-artwork}/icons/brightness-1.svg";
  brightness-2-icon = "${pkgs.ghaf-artwork}/icons/brightness-2.svg";
  brightness-3-icon = "${pkgs.ghaf-artwork}/icons/brightness-3.svg";
  brightness-4-icon = "${pkgs.ghaf-artwork}/icons/brightness-4.svg";
  brightness-5-icon = "${pkgs.ghaf-artwork}/icons/brightness-5.svg";
  brightness-6-icon = "${pkgs.ghaf-artwork}/icons/brightness-6.svg";
  brightness-7-icon = "${pkgs.ghaf-artwork}/icons/brightness-7.svg";
  brightness-8-icon = "${pkgs.ghaf-artwork}/icons/brightness-8.svg";
  bluetooth-1-icon = "${pkgs.ghaf-artwork}/icons/bluetooth-1.svg";

  power-icon = "${pkgs.ghaf-artwork}/icons/power.svg";
  restart-icon = "${pkgs.ghaf-artwork}/icons/restart.svg";
  suspend-icon = "${pkgs.ghaf-artwork}/icons/suspend.svg";

  settings-icon = "${pkgs.ghaf-artwork}/icons/admin-cog.svg";

  lock-icon = "${pkgs.ghaf-artwork}/icons/lock.svg";

  logout-icon = "${pkgs.ghaf-artwork}/icons/logout.svg";

  arrow-right-icon = "${pkgs.ghaf-artwork}/icons/arrow-right.svg";

  # Called by eww.yuck for updates and reloads
  ewwCmd = "${pkgs.eww}/bin/eww -c /etc/eww";

  eww-bat = pkgs.writeShellApplication {
    name = "eww-bat";
    runtimeInputs = [
      pkgs.gawk
      pkgs.bc
    ];
    bashOptions = [ ];
    text = ''
      icon() {
        if [ "$1" -lt 10 ]; then
            echo "${battery-0-icon}"
        elif [ "$1" -lt 30 ]; then
            echo "${battery-1-icon}"
        elif [ "$1" -lt 70 ]; then
            echo "${battery-2-icon}"
        else
            echo "${battery-3-icon}"
        fi
      }

      get() {
        BATTERY_PATH="/sys/class/power_supply/BAT0"
        ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now")
        POWER_NOW=$(cat "$BATTERY_PATH/power_now")
        CAPACITY=$(cat "$BATTERY_PATH/capacity")
        STATUS=$(cat "$BATTERY_PATH/status")
        ICON=$(icon "$CAPACITY")
        if [ "$STATUS" = "Charging" ]; then
            ICON="${battery-charging-icon}"
        fi
        if [ "$POWER_NOW" -eq 0 ]; then
            echo "{
                \"hours\": \"0\",
                \"minutes_total\": \"0\",
                \"minutes\": \"0\",
                \"status\": \"$STATUS\",
                \"capacity\": \"$CAPACITY\",
                \"icon\": \"$ICON\"
            }"
            exit
        fi

        TIME_REMAINING=$(echo "scale=2; $ENERGY_NOW / $POWER_NOW" | bc)
        HOURS=$(echo "$TIME_REMAINING" | awk '{print int($1)}')
        MINUTES_TOTAL=$(echo "$HOURS * 60" | bc | awk '{printf "%d\n", $1}')
        MINUTES_REMAINDER=$(echo "($TIME_REMAINING - $HOURS) * 60" | bc | awk '{printf "%d\n", $1}')

        # If both hours and minutes are 0, return 0 for both
        if [ "$HOURS" -eq 0 ] && [ "$MINUTES" -eq 0 ]; then
            HOURS=0
            MINUTES=0
        fi

        echo "{
            \"hours\": \"$HOURS\",
            \"minutes_total\": \"$MINUTES_TOTAL\",
            \"minutes\": \"$MINUTES_REMAINDER\",
            \"status\": \"$STATUS\",
            \"capacity\": \"$CAPACITY\",
            \"icon\": \"$ICON\"
        }"
      }

      case "$1" in
        get)
          get
          ;;
        *)
          echo "Usage: $0 {get}"
          ;;
      esac
    '';
  };

  ewwbar-ctrl = pkgs.writeShellApplication {
    name = "ewwbar-ctrl";
    runtimeInputs = [
      pkgs.wlr-randr
      pkgs.jq
      pkgs.bash
      pkgs.gawk
      pkgs.xorg.setxkbmap
    ];
    bashOptions = [ ];
    text = ''
      start() {
        # Get the number of connected displays using wlr-randr and parse the output with jq
        wlr_randr_output=$(wlr-randr --json)
        displays=$(echo "$wlr_randr_output" | jq 'length')

        # Check if there are any connected displays
        if [ "$displays" -eq 0 ]; then
            echo "No connected displays found."
            exit 1
        fi

        # Start eww daemon
        ${ewwCmd} kill
        ${ewwCmd} --force-wayland daemon
        sleep 0.2
        update-vars &

        # Launch ewwbar for each connected display
        mapfile -t displays < <(echo "$wlr_randr_output" | jq -r '.[] | select(.enabled == true) | .model')
        for display_name in "''${displays[@]}"; do
            echo Opening ewwbar on display "$display_name"
            ${ewwCmd} open --force-wayland --no-daemonize --screen "$display_name" bar --id bar:"$display_name" --arg screen="$display_name"
        done
      }

      # Reloads current config without opening new windows
      reload() {
        ${ewwCmd} reload
        update-vars
      }

      update-vars() {
        local volume
        ${lib.optionalString useGivc ''
          volume=$(${eww-volume}/bin/eww-volume get)
        ''}
        brightness=$(${eww-brightness}/bin/eww-brightness get)
        battery=$(${eww-bat}/bin/eww-bat get)
        keyboard_layout=$(setxkbmap -query | awk '/layout/{print $2}' | tr '[:lower:]' '[:upper:]')
        workspace=$(${ghaf-workspace}/bin/ghaf-workspace cur)
        if ! [[ $workspace =~ ^[0-9]+$ ]] ; then
            workspace="1"
        fi

        ${ewwCmd} update \
          volume="$volume" \
          brightness="$brightness" \
          battery="$battery" \
          keyboard_layout="$keyboard_layout" \
          workspace="$workspace"
      }

      kill() {
        ${ewwCmd} kill
      }

      case "$1" in
        start)
            start
            ;;
        reload)
            reload
            ;;
        kill)
            kill
            ;;
        *)
            echo "Usage: $0 {start|reload|kill}"
            exit 1
            ;;
      esac
    '';
  };

  eww-brightness = pkgs.writeShellApplication {
    name = "eww-brightness";
    runtimeInputs = [
      pkgs.gawk
      pkgs.brightnessctl
      pkgs.inotify-tools
    ];
    bashOptions = [ ];
    text = ''
      icon() {
          if [ "$1" -eq 0 ]; then
              echo "${brightness-0-icon}"
          elif [ "$1" -lt 12 ]; then
              echo "${brightness-1-icon}"
          elif [ "$1" -lt 25 ]; then
              echo "${brightness-2-icon}"
          elif [ "$1" -lt 37 ]; then
              echo "${brightness-3-icon}"
          elif [ "$1" -lt 50 ]; then
              echo "${brightness-4-icon}"
          elif [ "$1" -lt 62 ]; then
              echo "${brightness-5-icon}"
          elif [ "$1" -lt 75 ]; then
              echo "${brightness-6-icon}"
          elif [ "$1" -lt 87 ]; then
              echo "${brightness-7-icon}"
          else
              echo "${brightness-8-icon}"
          fi
      }

      get() {
          brightness=$(brightnessctl info | grep -oP '(?<=\().+?(?=%)' | awk '{print $1 + 0.0}')
          icon=$(icon "$brightness")
          echo "{ \"screen\": { \"level\": \"$brightness\" }, \"icon\": \"$icon\" }"
      }

      listen() {
        inotifywait -m -e close_write /sys/class/backlight/*/brightness |
        while read -r; do
            get &
        done
      }

      case "$1" in
        get)
          get
          ;;
        set_screen)
          brightnessctl set "$2%" -q
          ;;
        listen)
          listen
          ;;
        *)
          echo "Usage: $0 {get|set_screen|listen} [args...]"
          ;;
      esac
    '';
  };

  eww-volume = pkgs.writeShellApplication {
    name = "eww-volume";
    runtimeInputs = [
      pkgs.gawk
      pkgs.pulseaudio
      pkgs.pamixer
    ];
    bashOptions = [ ];
    text = ''
      export PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort}

      icon() {
          if [[ "$2" == "true" || "$1" -eq 0 ]]; then
              echo "${volume-0-icon}"
          elif [ "$1" -lt 25 ]; then
              echo "${volume-1-icon}"
          elif [ "$1" -lt 75 ]; then
              echo "${volume-2-icon}"
          else
              echo "${volume-3-icon}"
          fi
      }

      get() {
          volume=$(pamixer --get-volume)
          muted=$(pamixer --get-mute)
          icon=$(icon "$volume" "$muted")
          echo "{ \"level\": \"$volume\", \"muted\": \"$muted\", \"icon\": \"$icon\" }"
      }

      listen() {
        pactl subscribe | while read -r event; do
            if [[ "$event" == *"change"* ]]; then
                get &
            fi
        done
      }

      case "$1" in
        get)
          get
          ;;
        set_volume)
          pamixer --unmute --set-volume "$2"
          ;;
        mute)
          pamixer --toggle-mute
          ;;
        listen)
          listen
          ;;
        *)
          echo "Usage: $0 {get|set_volume|mute|listen} [args...]"
          ;;
      esac
    '';
  };

  eww-display = pkgs.writeShellApplication {
    name = "eww-display";
    runtimeInputs = [
      pkgs.wlr-randr
      pkgs.jq
      pkgs.inotify-tools
    ];
    bashOptions = [ ];
    text = ''
      mkdir -p ~/.config/eww
      echo 1 > ~/.config/eww/display && sleep 0.5

      open_bar() {
          local display_name=$1
          ${ewwCmd} open --force-wayland --no-daemonize --screen "$display_name" bar --id bar:"$display_name" --arg screen="$display_name"
      }

      close_bar() {
          local display_name=$1
          ${ewwCmd} close bar:"$display_name"
      }

      wlr_randr_output=$(wlr-randr --json)
      prev_displays=$(echo "$wlr_randr_output" | jq 'length')
      mapfile -t prev_display_names < <(echo "$wlr_randr_output" | jq -r '.[] | select(.enabled == true) | .model')

      inotifywait -m -e close_write ~/.config/eww/display | while read -r; do
          wlr_randr_output=$(wlr-randr --json)
          current_displays=$(echo "$wlr_randr_output" | jq 'length')
          mapfile -t current_display_names < <(echo "$wlr_randr_output" | jq -r '.[] | select(.enabled == true) | .model')

          if (( current_displays > prev_displays )); then
              # Open bars for added displays
              mapfile -t added_displays < <(comm -13 <(printf "%s\n" "''${prev_display_names[@]}" | sort) <(printf "%s\n" "''${current_display_names[@]}" | sort))
              for display_name in "''${added_displays[@]}"; do
                  open_bar "$display_name"
              done
          elif (( current_displays < prev_displays )); then
              # Close bars for removed displays
              mapfile -t removed_displays < <(comm -23 <(printf "%s\n" "''${prev_display_names[@]}" | sort) <(printf "%s\n" "''${current_display_names[@]}" | sort))
              for display_name in "''${removed_displays[@]}"; do
                  close_bar "$display_name"
              done
          fi

          # Update previous state
          prev_displays=$current_displays
          prev_display_names=("''${current_display_names[@]}")
      done
    '';
  };

  mkPopupHandler =
    {
      name,
      stateFile,
      popupName,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.inotify-tools ];
      # Needed to prevent script from exiting prematurely
      bashOptions = [ ];
      text = ''
        mkdir -p ~/.config/eww
        echo 1 > ~/.config/eww/${stateFile} && sleep 0.5
        popup_timer_pid=0

        show_popup() {
            if [ "$popup_timer_pid" -ne 0 ]; then
              kill "$popup_timer_pid" 2>/dev/null
              popup_timer_pid=0
            fi

            if ! ${ewwCmd} active-windows | grep -q "${popupName}"; then
              ${ewwCmd} open ${popupName}
              ${ewwCmd} update ${popupName}-visible="true"
            fi
            (
              sleep 2
              ${ewwCmd} update ${popupName}-visible="false"
              sleep 0.1
              ${ewwCmd} close ${popupName}
            ) &

            popup_timer_pid=$!
        }

        inotifywait -m -e close_write ~/.config/eww/${stateFile} |
        while read -r; do
            show_popup > /dev/null 2>&1
        done
      '';
    };
in
{
  config = lib.mkIf cfg.enable {
    # Main eww bar config
    environment.etc."eww/eww.yuck" = {
      text = ''
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							   Variables        					     ;;
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        (defpoll keyboard_layout :interval "5s" "${pkgs.xorg.setxkbmap}/bin/setxkbmap -query | ${pkgs.gawk}/bin/awk '/layout/{print $2}' | tr a-z A-Z")
        (defpoll battery  :interval "5s" :initial "{}" "${eww-bat}/bin/eww-bat get")
        (deflisten brightness "${eww-brightness}/bin/eww-brightness listen")
        (deflisten volume "${eww-volume}/bin/eww-volume listen")
        (deflisten workspace :initial "1" "${ghaf-workspace}/bin/ghaf-workspace subscribe")

        (defvar calendar_day "date '+%d'")
        (defvar calendar_month "date '+%-m'")
        (defvar calendar_year "date '+%Y'")

        (defvar volume-popup-visible "false")
        (defvar brightness-popup-visible "false")
        (defvar workspace-popup-visible "false")
        (defvar workspaces-visible "false")
        ;; (defpoll bluetooth  :interval "3s" :initial "{}" "${pkgs.bt-launcher}/bin/bt-launcher status")

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							    Widgets        							 ;;
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Launcher ;;
        (defwidget launcher []
            (button :class "icon_button"
                :onclick "${pkgs.nwg-drawer}/bin/nwg-drawer &"
                (box :class "icon"
                    :style "background-image: url(\"${launcher-icon}\")")))

        ;; Generic slider widget ;;
        (defwidget sys_slider [?header icon ?settings-icon level ?onchange ?settings-onclick ?icon-onclick ?class ?font-icon ?min]
            (box :orientation "v"
                :class "qs-slider"
                :spacing 10
                :space-evenly false
                (label :class "header"
                    :visible { header != "" && header != "null" ? "true" : "false" }
                    :text header
                    :halign "start"
                    :hexpand true)
                (box :orientation "h"
                    :valign "end"
                    :space-evenly false
                    (eventbox
                        :active { icon-onclick != "" && icon-onclick != "null" ? "true" : "false" }
                        :visible {font-icon == "" ? "true" : "false"}
                        :onclick icon-onclick
                        :hexpand false
                        :class "icon_settings"
                        (box :class "icon"
                            :hexpand false
                            :style "background-image: url(\"''${icon}\")"))
                    (label :class "icon" :visible {font-icon != "" ? "true" : "false"} :text font-icon)
                    (eventbox
                        :valign "CENTER"
                        :class "slider"
                        :hexpand true
                        (scale
                            :hexpand true
                            :orientation "h"
                            :halign "fill"
                            :value level
                            :onchange onchange
                            :max 101
                            :min { min ?: 0 }))
                    (eventbox
                        :visible { settings-onclick != "" && settings-onclick != "null" ? "true" : "false" }
                        :onclick settings-onclick
                        :class "settings"
                        (box :class "icon"
                            :hexpand false
                            :style "background-image: url(\"''${settings-icon}\")")))))

        (defwidget sys_sliders []
            (box
                :orientation "v"
                :spacing 10
                :hexpand false
                :space-evenly false
                (sys_slider
                        :header "Volume"
                        :icon {volume.icon}
                        :icon-onclick "${eww-volume}/bin/eww-volume mute &"
                        :settings-icon "${arrow-right-icon}"
                        :level { volume.muted == "true" ? "0" : volume.level }
                        :onchange "PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort} ${pkgs.pamixer}/bin/pamixer --unmute --set-volume {} &")
                (sys_slider
                        :header "Brightness"
                        :level {brightness.screen.level}
                        :icon {brightness.icon}
                        :min "5"
                        :onchange "${eww-brightness}/bin/eww-brightness set_screen {} &")))

        ;; Generic Widget Buttons For Quick Settings ;;
        (defwidget widget_button [icon ?title ?header ?subtitle ?onclick ?font-icon ?class]
            (eventbox :class { class == "" ? "widget-button" : "''${class}" }
                :onclick onclick
                (box :orientation "v"
                    :class "inner-box"
                    :spacing 6
                    :space-evenly false
                    (label :class "header"
                        :visible { header != "" && header != "null" ? "true" : "false" }
                        :text header
                        :hexpand true
                        :vexpand true
                        :halign "start"
                        :valign "fill")
                    (box :orientation "h"
                        :spacing 10
                        :valign "fill"
                        :halign "start"
                        :hexpand true
                        :vexpand true
                        :space-evenly false
                        (box :class "icon"
                            :visible {font-icon == "" ? "true" : "false"}
                            :valign "center"
                            :halign "start"
                            :hexpand false
                            :style "background-image: url(\"''${icon}\")")
                        (label :class "icon" :visible {font-icon != "" ? "true" : "false"} :text font-icon)
                        (box :class "text"
                            :valign "center"
                            :orientation "v"
                            :spacing 3
                            :halign "start"
                            :hexpand true
                            (label :halign "start" :class "title" :text title)
                            (label :visible {subtitle != "" ? "true" : "false"} :halign "start" :class "subtitle" :text subtitle :limit-width 13))))))

        ;; Power Menu Buttons ;;
        (defwidget power_menu []
            (box
            :orientation "v"
            :halign "start"
            :hexpand "false"
            :vexpand "false"
            :spacing 10
            :space-evenly "false"
            (widget_button
                    :class "power-menu-button"
                    :icon "${lock-icon}"
                    :title "Lock"
                    :onclick "''${EWW_CMD} close power-menu closer & loginctl lock-session &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${suspend-icon}"
                    :title "Suspend"
                    :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol suspend &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${logout-icon}"
                    :title "Log Out"
                    :onclick "''${EWW_CMD} close power-menu closer & ${pkgs.labwc}/bin/labwc --exit &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${restart-icon}"
                    :title "Reboot"
                    :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol reboot &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${power-icon}"
                    :title "Shutdown"
                    :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol poweroff &")))

        ${lib.optionalString useGivc ''
          ;; Quick Settings Buttons ;;
          (defwidget settings_buttons []
              (box
                  :orientation "v"
                  :spacing 10
                  (box
                      :orientation "h"
                      (widget_button
                          :icon "${bluetooth-1-icon}"
                          :header "Bluetooth"
                          :onclick "''${EWW_CMD} close quick-settings closer & ${pkgs.bt-launcher}/bin/bt-launcher &")
                      (box
                          :hexpand true
                          :vexpand true
                          :class "spacer"))))

            ;; Battery Widget In Quick Settings ;;
            (defwidget etc []
                (box :orientation "h"
                    :space-evenly true
                    :spacing 10
                    (widget_button
                        :visible { EWW_BATTERY != "" ? "true" : "false" }
                        :header "Battery"
                        :title {EWW_BATTERY != "" ? "''${battery.capacity}%" : "100%"}
                        :subtitle { battery.status == 'Charging' ? "Charging" :
                                    battery.hours != "0" && battery.minutes != "0" ? "''${battery.hours}h ''${battery.minutes}m" :
                                    battery.hours == "0" && battery.minutes != "0" ? "''${battery.minutes}m" :
                                    battery.hours != "0" && battery.minutes == "0" ? "''${battery.hours}h" :
                                    "" }
                        :icon {battery.icon})
                    (widget_button
                        :icon "${settings-icon}"
                        :header "Settings"
                        :onclick "''${EWW_CMD} close quick-settings closer & ${pkgs.ctrl-panel}/bin/ctrl-panel >/dev/null &")))
        ''}

        ;; Quick Settings Widget ;;
        (defwidget quick-settings-widget []
            (box :class "floating-widget"
                :orientation "v"
                :space-evenly false
                (box
                    :class "wrapper_widget"
                    :space-evenly false
                    :spacing 10
                    :orientation "v"
                    (etc)
                    (sys_sliders))))

        ;; Power Menu Widget ;;
        (defwidget power-menu-widget []
            (box :class "floating-widget"
                :orientation "v"
                :space-evenly false
                (box
                    :class "wrapper_widget"
                    :space-evenly false
                    :orientation "v"
                    (power_menu))))

        ;; Brightness Popup Widget ;;
        (defwidget brightness-popup []
            (revealer :transition "crossfade" :duration "200ms" :reveal brightness-popup-visible :active false
                (box :class "wrapper_widget"
                (box :class "hotkey"
                    (sys_slider
                        :valign "center"
                        :icon {brightness.icon}
                        :level {brightness.screen.level})))))

        ;; Volume Popup Widget ;;
        (defwidget volume-popup []
            (revealer :transition "crossfade" :duration "200ms" :reveal volume-popup-visible :active false
                (box :class "wrapper_widget"
                (box :class "hotkey"
                    (sys_slider
                        :valign "center"
                        :icon {volume.icon}
                        :level {volume.level})))))

        ;; Workspace Popup Widget ;;
        (defwidget workspace-popup []
            (revealer :transition "crossfade" :duration "200ms" :reveal workspace-popup-visible :active false
                (box :class "wrapper_widget"
                (box :class "hotkey"
                    (label :text "Desktop ''${workspace}")))))

        ;; Quick Settings Button ;;
        (defwidget quick-settings-button [screen bat-icon vol-icon bright-icon]
            (button :class "icon_button"
                :onclick "if ''${EWW_CMD} active-windows | grep -q 'quick-settings'; then \
                            ''${EWW_CMD} close closer quick-settings & \
                          else \
                            ''${EWW_CMD} close power-menu calendar & \
                            ''${EWW_CMD} open --screen \"''${screen}\" closer --arg window=\"quick-settings\" && ''${EWW_CMD} open --screen \"''${screen}\" quick-settings; \
                          fi &"
                (box :orientation "h"
                    :space-evenly "false"
                    :spacing 14
                    :valign "center"
                    (box :class "icon"
                        :hexpand false
                        :style "background-image: url(\"''${bright-icon}\")")
                    (box :class "icon"
                        :hexpand false
                        :style "background-image: url(\"''${vol-icon}\")")
                    (box :class "icon"
                        :hexpand false
                        :style "background-image: url(\"''${bat-icon}\")"))))

        ;; Power Menu Launcher ;;
        (defwidget power-menu-launcher [screen]
            (button :class "icon_button icon"
                :halign "center"
                :valign "center"
                :onclick "if ''${EWW_CMD} active-windows | grep -q 'power-menu'; then \
                            ''${EWW_CMD} close closer power-menu & \
                          else \
                            ''${EWW_CMD} close quick-settings calendar & \
                            ''${EWW_CMD} open --screen \"''${screen}\" closer --arg window=\"power-menu\" && ''${EWW_CMD} open --screen \"''${screen}\" power-menu; \
                          fi &"
                (box :class "icon"
                    :hexpand false
                    :style "background-image: url(\"${power-icon}\")")))
        ;; Closer Widget ;;
        ;; This widget, and the closer window, acts as a transparent area that fills the whole screen
        ;; so the user can close the specified window (widget) simply by clicking "outside"
        (defwidget closer [window]
            (eventbox :onclick "(''${EWW_CMD} close ''${window} closer) &"))
        ;; Quick Settings Launcher ;;
        (defwidget control [screen]
            (box :orientation "h"
                :space-evenly "false"
                :spacing 14
                :valign "center"
                :class "control"
                (quick-settings-button :screen screen
                    :bright-icon {brightness.icon}
                    :vol-icon {volume.icon}
                    :bat-icon {battery.icon})))

        ;; Divider ;;
        (defwidget divider []
            (box
                :active false
                :orientation "v"
                :class "divider"))

        ;; Language ;;
        (defwidget language []
            (box
                :class "keyboard-layout"
                :halign "center"
                :valign "center"
                :visible "false"
                (label  :text keyboard_layout)))

        ;; Clock ;;
        (defwidget time []
            (label
                :text "''${formattime(EWW_TIME, "%H:%M")}"
                :class "time"))

        ;; Date ;;
        (defwidget date [screen]
            (button
                :onclick "''${EWW_CMD} update calendar_day=\"$(date +%d)\" calendar_month=\"$(date +%-m)\" calendar_year=\"$(date +%Y)\" & \
                          if ''${EWW_CMD} active-windows | grep -q 'calendar'; then \
                            ''${EWW_CMD} close closer calendar & \
                          else \
                            ''${EWW_CMD} close quick-settings power-menu & \
                            ''${EWW_CMD} open --screen \"''${screen}\" closer --arg window=\"calendar\" && ''${EWW_CMD} open --screen \"''${screen}\" calendar; \
                          fi &"
                :class "icon_button date" "''${formattime(EWW_TIME, "%a %b %-d")}"))

        ;; Calendar ;;
        (defwidget cal []
            (box :class "floating-widget"
                (box :class "wrapper_widget"
                    (calendar :class "cal"
                        :show-week-numbers false
                        :day calendar_day
                        :month calendar_month
                        :year calendar_year))))

        ;; Left Widgets ;;
        (defwidget workspaces []
            (box :class "workspace"
                :orientation "h"
                :space-evenly "false"
                (button :class "icon_button"
                        :tooltip "Current desktop"
                        :onclick {workspaces-visible == "false" ? "''${EWW_CMD} update workspaces-visible=true" : "''${EWW_CMD} update workspaces-visible=false"}
                        workspace)
                (revealer
                    :transition "slideright"
                    :duration "250ms"
                    :reveal workspaces-visible
                    (eventbox :onhoverlost "''${EWW_CMD} update workspaces-visible=false"
                        (box :orientation "h"
                            :space-evenly "true"
                            ${
                              lib.concatStringsSep "\n" (
                                builtins.map (index: ''
                                  (button :class "icon_button"
                                      :onclick "${ghaf-workspace}/bin/ghaf-workspace switch ${toString index}; ''${EWW_CMD} update workspaces-visible=false"
                                      "${toString index}")
                                '') (lib.lists.range 1 cfg.maxDesktops)
                              )
                            })))))

        (defwidget left []
            (box
                :orientation "h"
                :space-evenly "false"
                :spacing 14
                :halign "start"
                :valign "center"
                (launcher)
                (divider)
                (workspaces)))

        ;; Right Widgets ;;
        (defwidget datetime-locale [screen]
            (box
                :orientation "h"
                :space-evenly "false"
                :spacing 14
                (language)
                (box
                    :orientation "h"
                    :space-evenly "false"
                    :spacing 14
                    (time)
                    (date :screen screen))))

        ;; End Widgets ;;
        (defwidget end [screen]
            (box :orientation "h"
                :space-evenly "false"
                :halign "end"
                :valign "center"
                :spacing 14
                (systray :orientation "h" :spacing 14 :prepend-new true :class "tray")
                (divider)
                ${lib.optionalString useGivc "(control :screen screen) (divider)"}
                (datetime-locale :screen screen)
                (divider)
                (power-menu-launcher :screen screen)))

        ;; Bar ;;
        (defwidget bar [screen]
            (box
                :class "eww_bar"
                :orientation "h"
                :vexpand "false"
                :hexpand "false"
                (left)
                (end :screen screen)))

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							       Windows   							 ;;
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Bar Window ;;
        (defwindow bar [screen]
            :geometry (geometry
                        :x "0px"
                        :y "0px"
                        :height "36px"
                        :width "100%"
                        :anchor "top center")
            :focusable "false"
            :hexpand "false"
            :vexpand "false"
            :stacking "fg"
            :exclusive "true"
            (bar :screen screen))

        ;; Calendar Window ;;
        (defwindow calendar
            :geometry (geometry :y "0px"
                                :x "0px"
                                :anchor "top right")
            :stacking "fg"
            (cal))

        ;; Power menu window ;;
        (defwindow power-menu
            :geometry (geometry :y "0px"
                                :x "0px"
                                :anchor "top right")
            :stacking "fg"
            (power-menu-widget))

        ${lib.optionalString useGivc ''
          ;; Quick settings window ;;
          (defwindow quick-settings
              :geometry (geometry :y "0px"
                                  :x "0px"
                                  :anchor "top right")
              :stacking "fg"
              (quick-settings-widget))


          ;; Volume Popup Window ;;
          (defwindow volume-popup
              :monitor 0
              :geometry (geometry :y "150px"
                                  :x "0px"
                                  :anchor "bottom center")
              :stacking "overlay"
              (volume-popup))

          ;; Brightness Popup Window ;;
          (defwindow brightness-popup
              :monitor 0
              :geometry (geometry :y "150px"
                                  :x "0px"
                                  :anchor "bottom center")
              :stacking "overlay"
              (brightness-popup))

          ;; Workspace Popup Window ;;
          (defwindow workspace-popup
              :monitor 0
              :geometry (geometry :y "150px"
                                  :x "0px"
                                  :anchor "bottom center")
              :stacking "overlay"
              (workspace-popup))
        ''}

        ;; Closer Window ;;
        (defwindow closer [window]
            :geometry (geometry :width "100%" :height "100%")
            :stacking "fg"
            :focusable false
            (closer :window window))
      '';

      # The UNIX file mode bits
      mode = "0644";
    };
    # Main eww bar styling
    environment.etc."eww/eww.scss" = {
      text = ''
        $bg-primary: #121212;
        $widget-bg: #1A1A1A;
        $widget-hover: #282828;
        $bg-secondary: #2B2B2B;
        $text-base: #FFFFFF;
        $text-disabled: #9c9c9c;
        $text-success: #5AC379;
        $icon-subdued: #3D3D3D;
        $stroke-success: #5AC379;
        $font-bold: 600;

        @mixin unset($rec: false) {
            all: unset;

            @if $rec {
                * {
                    all: unset
                }
            }
        }

        * {
            color: $text-base;
            font-family: "${cfg.gtk.fontName}";
            font-size: 14px;
            :disabled {
                color: $text-disabled;
            }
        }

        window.background {
            background-color: transparent;
        }

        tooltip {
            background-color: $bg-primary;
        }

        @mixin widget($bg: #161616, $padding: 10px, $radius: 12px){
            border-radius: $radius;
            background-color: $bg;
            padding: $padding;
        }

        @mixin wrapper_widget($padding: 14px, $radius: 6px){
            @include widget($padding: 14px, $radius: 6px, $bg: $bg-primary);
        }

        @mixin floating_widget($margin: 0.3em 0.3em 0em 0em, $padding: 14px, $radius: 6px, $unset: true) {
            @if $unset {
              @include unset($rec: true);
            }
            border-radius: $radius;
            margin: $margin;

            .wrapper_widget { @include wrapper_widget($padding: $padding, $radius: $radius); }
        }

        @mixin icon(){
            background-color: transparent;
            background-repeat: no-repeat;
            background-position: center;
            background-size: contain;
            min-height: 24px;
            min-width: 24px;
            font-family: Fira Code;
            font-size: 1.5em;
            color: #FFFFFF;
        }

        @mixin icon-button($bg: transparent, $hover-bg: $widget-hover) {
            @include unset;
            @include icon;

            border-radius: 0.25em;
            padding: 0.3em;
            background-color: $bg;

            .icon{
                @include icon;
            }

            &:hover {
                transition: 200ms linear background-color;
                background-color: $hover-bg;
            }

            &:active {
                transition: 200ms linear background-color;
                background-color: #1F1F1F;
            }
        }

        @mixin slider($slider-width: 225px, $slider-height: 2px, $thumb: true, $thumb-width: 1em, $focusable: true, $radius: 7px, $shadows: true, $trough-bg: $widget-hover) {
            trough {
                border-radius: $radius;
                border: 0;
                background-color: $trough-bg;
                min-height: $slider-height;
                min-width: $slider-width;
                margin: $thumb-width / 2;

                highlight,
                progress {
                    background-color: $stroke-success;
                    border-radius: $radius;
                }
            }

            slider {
                @if $thumb {
                    box-shadow: none;
                    background-color: #D3D3D3;
                    border: 0 solid transparent;
                    border-radius: 50%;
                    min-height: $thumb-width;
                    min-width: $thumb-width;
                    margin: -($thumb-width / 2) 0;
                } @else {
                    margin: 0;
                    min-width: 0;
                    min-height: 0;
                    background-color: transparent;
                }
            }

            &:hover {
                slider {
                    @if $thumb {
                        background-color: #D3D3D3;

                        @if $shadows {
                            box-shadow: 0px 0px 3px 0px $bg-primary;
                        }
                    }
                }
            }

            &:disabled {
                highlight,
                progress {
                    background-image: none;
                }
            }

            @if $focusable {
                trough:focus {
                    box-shadow: inset 0px 0px 0px 1px $bg-primary;

                    slider {
                        @if $thumb {
                            background-color: red;
                            box-shadow: inset 0px 0px 0px 1px $bg-primary;
                        }
                    }
                }

            }
        }

        @mixin sys-sliders () {
            .slider{ @include slider; }

            .header {
                font-size: 0.9em;
                font-weight: 500;
                font-family: ${cfg.gtk.fontName};
            }

            .settings{
                @include icon-button;
                margin-left: 0.15em;
            }

            .icon_settings{
                @include icon-button;
                margin-right: 0.15em;
            }
        }

        @mixin qs-widget($min-height: 70px, $min-width: 150px, $radius: 0.75em, $bg: $widget-bg) {
            min-height: $min-height;
            min-width: $min-width;
            border-radius: $radius;
            background-color: $bg;
        }

        @mixin widget-button($min-width: 133px, $min-height: 58px, $radius: 0.75em, $bg: $widget-bg, $padding: 0.8em, $icon-padding: 0) {
            @include qs-widget($min-width: $min-width, $min-height: $min-height);

            .inner-box {
                padding: $padding;
                min-width: $min-width;
                min-height: $min-height;
            }

            &:hover {
                transition: 200ms linear background-color;
                background-color: $widget-hover;
            }

            &:active {
                transition: 200ms linear background-color;
                background-color: #1F1F1F;
            }

            .icon {
                background-color: transparent;
                background-repeat: no-repeat;
                background-position: center;
                min-height: 24px;
                min-width: 24px;
                padding: $icon-padding;
            }

            .text {
                .header {
                    font-weight: 600;
                    font-size: 1em;
                }

                .title {
                    font-size: 0.9em;
                    font-weight: 500;
                    font-family: ${cfg.gtk.fontName};
                }

                .subtitle {
                    font-weight: 400;
                    font-size: 0.8em;
                    min-height: 0px;
                }
            }
        }

        .qs-widget {
            @include unset($rec: true);
            @include qs-widget;
        }

        .wrapper_widget {
            @include unset($rec: true);
            @include wrapper_widget;
        }

        .icon { @include icon; }

        .floating-widget { @include floating_widget; }

        .qs-slider {
            @include unset($rec: true);
            @include sys-sliders;
            @include qs-widget($min-height: 0px);
            padding: 0.8em;
        }

        .hotkey {
            @include floating_widget($margin: 0, $padding: 10px 12px);
            @include icon;
            .slider{ @include slider($slider-width: 150px, $thumb: false, $slider-height: 5px); }
            font-size: 1.3em;
        }

        .widget-button {@include widget-button; }

        .power-menu-button {@include widget-button($min-height: 33px); }

        .eww_bar {
            background-color: $bg-primary;
            padding: 0.2em 1em 0.2em 1em;
        }

        .icon_button {
            @include icon-button;
        }

        .divider {
            background-color: $icon-subdued;
            padding-left: 1px;
            padding-right: 1px;
            border-radius: 10px;
        }

        .time {
            padding: 0.4em 0.25em;
            border-radius: 0.25em;
            background-color: $bg-primary;
            font-weight: $font-bold;
            font-size: 1em;
        }

        .date {
            padding: 0.4em 0.25em;
            border-radius: 0.25em;
            font-weight: $font-bold;
            font-size: 1em;
        }

        .keyboard-layout {
            padding: 0.4em 0.25em;
            border-radius: 4px;
            background-color: $bg-primary;
            font-weight: $font-bold;
            font-size: 1em;
        }

        .workspace {
            font-size: 1.2em;
            font-weight: $font-bold;
        }

        .spacer {
            background-color: transparent;
        }

        .cal {
            font-size: 1.2em;
            padding: 0.2em 0.2em;

            calendar {
                font-size: 1.2em;
                padding: 0.2em 0.2em;

                &.header {
                    font-weight: $font-bold;
                    font-size: 1.5em;
                }

                &.button {
                    color: $stroke-success;
                    padding: 0.3em;
                    border-radius: 4px;
                    border: none;

                    &:hover {
                        background-color: $bg-secondary;
                    }
                }

                &.stack.month {
                    padding: 0 5px;
                }
                &.label.year {
                    padding: 0 5px;
                }

                &:selected {
                    color: $text-success;
                }

                &:indeterminate {
                    color: $text-disabled;
                }
            }
        }

        .tray menu {
            font-family: ${cfg.gtk.fontName};
            font-size: 1.1em;
            background-color: $bg-primary;

            >menuitem {
                font-size: 1em;
                padding: 5px 7px;

                &:hover {
                    background-color: $widget-hover;
                }

                >check {
                  border-width: 1px;
                  border-color: transparent;
                  min-height: 16px;
                  min-width: 16px;
                  color: transparent;
                  background-color: transparent;

                  &:checked {
                    border-color: $text-base;
                    color: $text-base;
                  }
                }

                >arrow {
                    color: $text-base;
                    background-color: transparent;
                    margin-left: 10px;
                    min-height: 16px;
                    min-width: 16px;
                }
            }

            >arrow {
                background-color: transparent;
                color: $text-base;
            }

            separator {
                background-color: $icon-subdued;
                padding-top: 1px;
                padding-bottom: 1px;
                border-radius: 10px;

                &:last-child {
                    padding: unset;
                }
            }
        }
      '';

      # The UNIX file mode bits
      mode = "0644";
    };

    services.udev.extraRules = ''
      ACTION=="change", SUBSYSTEM=="drm", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="eww-display-trigger.service"
    '';

    systemd.user.services.ewwbar = {
      enable = true;
      description = "ewwbar";
      serviceConfig = {
        Type = "forking";
        ExecStart = "${ewwbar-ctrl}/bin/ewwbar-ctrl start";
        ExecReload = "${ewwbar-ctrl}/bin/ewwbar-ctrl reload";
        Environment = "XDG_CACHE_HOME=/tmp/.ewwcache";
        Restart = "always";
        RestartSec = "100ms";
      };
      startLimitIntervalSec = 0;
      wantedBy = [ "ghaf-session.target" ];
      partOf = [ "ghaf-session.target" ];
      requires = [ "ghaf-session.target" ];
    };

    systemd.user.services.eww-brightness-popup = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${
          mkPopupHandler {
            name = "brightness-popup-handler";
            stateFile = "brightness";
            popupName = "brightness-popup";
          }
        }/bin/brightness-popup-handler";
        Restart = "on-failure";
      };
      after = [ "ewwbar.service" ];
      wantedBy = [ "ewwbar.service" ];
      partOf = [ "ghaf-session.target" ];
    };

    systemd.user.services.eww-display-trigger = {
      description = "eww-display-trigger";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo 1 > ~/.config/eww/display'";
      };
      after = [ "ewwbar.service" ];
    };

    systemd.user.services.eww-display-handler = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${eww-display}/bin/eww-display";
        Restart = "on-failure";
      };
      after = [ "ewwbar.service" ];
      wantedBy = [ "ewwbar.service" ];
      partOf = [ "ghaf-session.target" ];
    };

    systemd.user.services.eww-volume-popup = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${
          mkPopupHandler {
            name = "volume-popup-handler";
            stateFile = "volume";
            popupName = "volume-popup";
          }
        }/bin/volume-popup-handler";
        Restart = "on-failure";
      };
      after = [ "ewwbar.service" ];
      wantedBy = [ "ewwbar.service" ];
      partOf = [ "ghaf-session.target" ];
    };

    systemd.user.services.eww-workspace-popup = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${
          mkPopupHandler {
            name = "workspace-popup-handler";
            stateFile = "workspace";
            popupName = "workspace-popup";
          }
        }/bin/workspace-popup-handler";
        Restart = "on-failure";
      };
      after = [ "ewwbar.service" ];
      wantedBy = [ "ewwbar.service" ];
      partOf = [ "ghaf-session.target" ];
    };
  };
}
