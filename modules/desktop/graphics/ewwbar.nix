# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (builtins) replaceStrings;
  inherit (lib) optionalString;

  cfg = config.ghaf.graphics.labwc;
  audio-ctrl = pkgs.callPackage ../../../packages/audio-ctrl { };
  ghaf-workspace = pkgs.callPackage ../../../packages/ghaf-workspace { };

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
  eww = "${pkgs.eww}/bin/eww -c /etc/eww";

  cliArgs = replaceStrings [ "\n" ] [ " " ] ''
    --name ${config.ghaf.givc.adminConfig.name}
    --addr ${config.ghaf.givc.adminConfig.addr}
    --port ${config.ghaf.givc.adminConfig.port}
    ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
    ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/gui-vm-cert.pem"}
    ${optionalString config.ghaf.givc.enableTls "--key /run/givc/gui-vm-key.pem"}
    ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
  '';

  eww-popup = pkgs.writeShellApplication {
    name = "eww-popup";
    runtimeInputs = [ ];
    bashOptions = [ ];
    text = ''
      windows=("calendar" "quick-settings" "power-menu")

      close-others(){
          active_windows=$(${eww} active-windows)
          close=()

          for window in "''${windows[@]}"; do
              window_open=$(echo "$active_windows" | grep "$window")
              if [ "$window" != "$1" ] && [ -n "$window_open" ]; then
                  close+=("$window")
              fi
          done
          ${eww} close "''${close[@]}"
      }

      open-window(){
          close-others "$1"
          if [ -z "$2" ]; then
              ${eww} open --toggle "$1"
          else
              ${eww} open --toggle --screen "$2" "$1"
          fi
      }

      open-window "$1" "$2"
    '';
  };

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

      [ "$1" = "get" ] && get && exit
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
        displays=$(wlr-randr --json | jq 'length')
        
        # Check if there are any connected displays
        if [ "$displays" -eq 0 ]; then
            echo "No connected displays found."
            exit 1
        fi

        echo "Found connected displays: $displays"

        # Start eww daemon
        ${eww} kill
        ${eww} daemon
        sleep 0.2
        update-vars
        sleep 0.2

        # Launch ewwbar for each connected display
        for ((display=0; display<displays; display++)); do
            echo Starting ewwbar for display $display
            ${eww} open --no-daemonize --screen "$display" bar --id bar:$display --arg screen="$display"
        done

        # Open a widget for hotkey indicators only on main display
        ${eww} open --no-daemonize hotkey-indicator
      }

      # Reloads current config without opening new windows
      reload() {
        ${eww} reload
        update-vars
      }

      update-vars() {
        volume=$(${eww-volume}/bin/eww-volume get)
        brightness=$(${eww-brightness}/bin/eww-brightness get)
        battery=$(${eww-bat}/bin/eww-bat get)
        keyboard_layout=$(setxkbmap -query | awk '/layout/{print $2}' | tr '[:lower:]' '[:upper:]')
        workspace=$(${ghaf-workspace}/bin/ghaf-workspace cur)
        if ! [[ $workspace =~ ^[0-9]+$ ]] ; then
            workspace="1"
        fi
        
        ${eww} update \
          volume="$volume" \
          brightness="$brightness" \
          battery="$battery" \
          keyboard_layout="$keyboard_layout" \
          workspace="$workspace"
      }

      kill() {
        ${eww} kill
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
      timer_pid=0

      handle_hotkey_indicator() {
          if [ "$timer_pid" -ne 0 ]; then
              kill "$timer_pid" 2>/dev/null
          fi
          if ! ${eww} active-windows | grep -q "quick-settings"; then
              ${eww} update hotkey-source="brightness" hotkey-brightness-visible="true"
          fi
          ( sleep 2; ${eww} update hotkey-brightness-visible="false") &
          timer_pid=$!
      }

      screen_level() {
          brightnessctl info | grep -oP '(?<=\().+?(?=%)' | awk '{print $1 + 0.0}'
      }

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

      set_screen() {
          brightnessctl set "$1""%" -q
      }

      get() {
          brightness=$(screen_level)
          icon=$(icon "$brightness")
          echo "{ \"screen\": { \"level\": \"$brightness\" }, \"icon\": \"$icon\" }"
      }

      listen() {
        inotifywait -m /sys/class/backlight/*/brightness | \
        while read -r line; do
            if echo "$line" | grep -q "CLOSE_WRITE"; then
                handle_hotkey_indicator
                get
            fi
        done
      }

      if [[ "$1" == 'get' ]]; then get; fi
      if [[ "$1" == 'set_screen' ]]; then set_screen "$2"; fi
      if [[ "$1" == 'listen' ]]; then listen; fi
    '';
  };

  eww-volume = pkgs.writeShellApplication {
    name = "eww-volume";
    runtimeInputs = [
      pkgs.gawk
      pkgs.pulseaudio
      audio-ctrl
    ];
    bashOptions = [ ];
    text = ''
        timer_pid=0

        handle_hotkey_indicator() {
            if [ "$timer_pid" -ne 0 ]; then
                kill "$timer_pid" 2>/dev/null
            fi

            if ! ${eww} active-windows | grep -q "quick-settings"; then
                ${eww} update hotkey-source="volume" hotkey-volume-visible="true"
            fi
            ( sleep 2; ${eww} update hotkey-volume-visible="false") &
            timer_pid=$!
        }

      volume_level() {
          audio-ctrl get | awk '{print $1 + 0.0}'
      }

      is_muted() {
          audio-ctrl get_mut
      }

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

      set_volume() {
          audio-ctrl set "$1"
      }

      mute() {
          audio-ctrl mut
      }

      get() {
          volume=$(volume_level)
          muted=$(is_muted)
          icon=$(icon "$volume" "$muted")
          echo "{ \"level\": \"$volume\", \"muted\": \"$muted\", \"icon\": \"$icon\" }"
      }

      listen() {
        # Initialize variables to store previous volume and mute state
        prev_volume=""
        prev_mute_status=""

        pactl -s audio-vm:4713 subscribe | while read -r event; do
            if echo "$event" | grep -q "sink"; then
                current_volume=$(volume_level)
                current_mute_status=$(is_muted)

                # Check if volume or mute status changed
                if [[ "$current_volume" != "$prev_volume" || "$current_mute_status" != "$prev_mute_status" ]]; then
                    handle_hotkey_indicator
                    get

                    # Update previous states
                    prev_volume="$current_volume"
                    prev_mute_status="$current_mute_status"
                fi
            fi
        done
      }

      if [[ "$1" == 'get' ]]; then get; fi
      if [[ "$1" == 'set_volume' ]]; then set_volume "$2"; fi
      if [[ "$1" == 'listen' ]]; then listen; fi
      if [[ "$1" == 'mute' ]]; then mute; fi
    '';
  };

  eww-power = pkgs.writeShellApplication {
    name = "eww-power";
    runtimeInputs = [ pkgs.givc-cli ];
    bashOptions = [ ];
    text = ''
      if [ $# -ne 1 ]; then
      echo "Usage: $0 {reboot|poweroff|suspend}"
      fi

      case "$1" in (reboot|poweroff|suspend)
          givc-cli ${cliArgs} "$1"
          ;;
      *)
          echo "Invalid argument: $1"
          echo "Usage: $0 {reboot|poweroff|suspend}"
          ;;
      esac
    '';
  };

in
{
  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {
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

        (defvar hotkey-brightness-visible "false")
        (defvar hotkey-volume-visible "false")
        (defvar hotkey-source "volume")
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
                        :onchange "${eww-volume}/bin/eww-volume set_volume {} &")
                (sys_slider
                        :header "Display"
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
                    :icon "${power-icon}"
                    :title "Shutdown"
                    :onclick "${eww-popup}/bin/eww-popup power-menu & ${eww-power}/bin/eww-power poweroff &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${suspend-icon}"
                    :title "Suspend"
                    :onclick "${eww-popup}/bin/eww-popup power-menu & ${eww-power}/bin/eww-power suspend &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${restart-icon}"
                    :title "Reboot"
                    :onclick "${eww-popup}/bin/eww-popup power-menu & ${eww-power}/bin/eww-power reboot &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${logout-icon}"
                    :title "Log Out"
                    :onclick "${eww-popup}/bin/eww-popup power-menu & ${pkgs.labwc}/bin/labwc --exit &")
            (widget_button
                    :class "power-menu-button"
                    :icon "${lock-icon}"
                    :title "Lock"
                    :onclick "${eww-popup}/bin/eww-popup power-menu & loginctl lock-session &")))

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
                        :onclick "${eww-popup}/bin/eww-popup quick-settings & ${pkgs.bt-launcher}/bin/bt-launcher &")
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
                    :onclick "${eww-popup}/bin/eww-popup quick-settings & ${pkgs.ctrl-panel}/bin/ctrl-panel >/dev/null &")))

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
                    (sys_sliders)
                    (settings_buttons))))

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

        ;; Generic Hotkey Indicator Widget ;;
        (defwidget hotkey_indicator [icon level] 
            (box :class "hotkey" 
                :active false
                (sys_slider
                    :valign "center"
                    :icon icon
                    :level level)))

        ;; Hotkeys Widget ;;
        (defwidget hotkeys []
            (revealer :transition "crossfade" :duration "200ms" :reveal { hotkey-brightness-visible || hotkey-volume-visible }
                (box :vexpand false
                    :hexpand false
                    :orientation "v"
                    :class "wrapper_widget"
                    (stack :transition "none"
                        :selected { hotkey-source == "brightness" ? "0" : "1" }
                        (hotkey_indicator
                            :icon {brightness.icon}
                            :level {brightness.screen.level})
                        (hotkey_indicator
                            :icon {volume.icon}
                            :level { volume.muted == "true" ? "0" : volume.level })))))

        ;; Quick Settings Button ;;
        (defwidget quick-settings-button [screen bat-icon vol-icon bright-icon]
            (button :class "icon_button" :onclick "${eww-popup}/bin/eww-popup quick-settings ''${screen} &"
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
                :onclick "${eww-popup}/bin/eww-popup power-menu ''${screen} &"
                (box :class "icon"
                    :hexpand false
                    :style "background-image: url(\"${power-icon}\")")))

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
                (label  :text keyboard_layout)))

        ;; Clock ;;
        (defwidget time []
            (label 
                :text "''${formattime(EWW_TIME, "%H:%M")}"
                :class "time"))

        ;; Date ;;
        (defwidget date [screen]
            (button 
                :onclick "''${EWW_CMD} update calendar_day=\"$(date +%d)\" calendar_month=\"$(date +%-m)\" calendar_year=\"$(date +%Y)\"; ${eww-popup}/bin/eww-popup calendar ''${screen} &"
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
                        :tooltip "Current workspace"
                        :onclick {workspaces-visible == "false" ? "''${EWW_CMD} update workspaces-visible=true" : "''${EWW_CMD} update workspaces-visible=false"}
                        workspace)
                (revealer 
                    :transition "slideright"
                    :duration "250ms"
                    :reveal workspaces-visible
                    (eventbox :onhoverlost "''${EWW_CMD} update workspaces-visible=false"
                        (box :orientation "h"
                            :space-evenly "true"
                            (button :class "icon_button"
                                :onclick "${ghaf-workspace}/bin/ghaf-workspace switch 1; ''${EWW_CMD} update workspaces-visible=false"
                                "1")
                            (button :class "icon_button"
                                :onclick "${ghaf-workspace}/bin/ghaf-workspace switch 2; ''${EWW_CMD} update workspaces-visible=false"
                                "2"))))))

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
                    :space-evenly "true" 
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
                (systray :prepend-new true :class "tray")
                (divider)
                (control :screen screen)
                (divider)
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
            :wm-ignore true
            :windowtype "normal"
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

        ;; Quick settings window ;;
        (defwindow quick-settings
            :geometry (geometry :y "0px" 
                                :x "0px"
                                :anchor "top right")
            :stacking "fg"
            (quick-settings-widget))

        ;; Power menu window ;;
        (defwindow power-menu
            :geometry (geometry :y "0px" 
                                :x "0px"
                                :anchor "top right")
            :stacking "fg"
            (power-menu-widget))

        ;; Hotkey indicator window ;;
        (defwindow hotkey-indicator
            :monitor 0
            :geometry (geometry :y "150px" 
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            (hotkeys))
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
            font-family: "Inter";
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
                font-family: Inter;
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
                    font-family: Inter;
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
            font-family: Inter;
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
      ACTION=="change", SUBSYSTEM=="drm", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="eww-restart.service"
    '';

    systemd.user.services.ewwbar = {
      enable = true;
      description = "ewwbar";
      serviceConfig = {
        Type = "forking";
        ExecStart = "${ewwbar-ctrl}/bin/ewwbar-ctrl start";
        ExecReload = "${ewwbar-ctrl}/bin/ewwbar-ctrl kill";
        Environment = "XDG_CACHE_HOME=/tmp/.ewwcache";
        Restart = "always";
        RestartSec = "100ms";
      };
      wantedBy = [ "ghaf-session.target" ];
      partOf = [ "ghaf-session.target" ];
    };

    systemd.user.services.eww-restart = {
      description = "eww-restart";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "systemctl --user reload ewwbar.service || true";
      };
      after = [ "ewwbar.service" ];
    };
  };
}
