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

  launcher-icon = "${pkgs.ghaf-artwork}/icons/launcher.svg";
  security-icon = "${pkgs.ghaf-artwork}/icons/security-green.svg";

  battery-0-icon = "${pkgs.ghaf-artwork}/icons/battery-0.svg";
  battery-1-icon = "${pkgs.ghaf-artwork}/icons/battery-1.svg";
  battery-2-icon = "${pkgs.ghaf-artwork}/icons/battery-2.svg";
  battery-3-icon = "${pkgs.ghaf-artwork}/icons/battery-3.svg";
  battery-charging-icon = "${pkgs.ghaf-artwork}/icons/battery-charging.svg";

  wifi-0-icon = "${pkgs.ghaf-artwork}/icons/wifi-0.svg";
  wifi-1-icon = "${pkgs.ghaf-artwork}/icons/wifi-1.svg";
  wifi-2-icon = "${pkgs.ghaf-artwork}/icons/wifi-2.svg";
  wifi-3-icon = "${pkgs.ghaf-artwork}/icons/wifi-3.svg";
  wifi-4-icon = "${pkgs.ghaf-artwork}/icons/wifi-4.svg";

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

  arrow-right-icon = "${pkgs.ghaf-artwork}/icons/arrow-right.svg";

  # Colors
  ## Background
  bg-secondary = "#2B2B2B";
  ## Text
  text-base = "#FFFFFF";
  text-success = "#5AC379";
  ## Icons
  icon-subdued = "#3D3D3D";
  ## Stroke
  stroke-success = "#5AC379";

  # Typography
  font-bold = "600";

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
      widgets=("calendar" "quick-settings" "power-menu")
      widgets_to_close=()

      close-others(){
          for widget in "''${widgets[@]}"; do
              if [ "$widget" != "$1" ]; then
                  widgets_to_close+=("$widget")
              fi
          done
          ${eww} close "''${widgets_to_close[@]}" >/dev/null 2>&1
      }

      open-widget(){
          close-others "$1"
          if [ -z "$2" ]; then
              ${eww} open --toggle "$1"
          else
              ${eww} open --toggle --screen "$2" "$1"
          fi
      }

      if [ "$1" = "calendar" ]; then
          ${eww} update calendar_day="$(date +%d)" calendar_month="$(date +%-m)" calendar_year="$(date +%Y)"
      fi
      open-widget "$1" "$2"
    '';
  };

  eww-wifi = pkgs.writeShellApplication {
    name = "eww-wifi";
    runtimeInputs = [
      pkgs.jq
      pkgs.grpcurl
    ];
    bashOptions = [ ];
    text = ''
      grpcurl_cmd_get_active_connection="grpcurl -plaintext 192.168.100.1:9000 wifimanager.WifiService.GetActiveConnection"

      signal() {
          signal_level=$(echo "$1" | jq '.Signal // empty')
          echo "$signal_level"
      }

      icon() {
          if [ "$1" -lt 30 ]; then
              echo "${wifi-1-icon}"
          elif [ "$1" -lt 60 ]; then
              echo "${wifi-2-icon}"
          elif [ "$1" -lt 80 ]; then
              echo "${wifi-3-icon}"
          else
              echo "${wifi-4-icon}"
          fi
      }

      get() {
          active_connection=$($grpcurl_cmd_get_active_connection)

          signal=$(signal "$active_connection")
          icon=$(icon "$signal")
          connected=$(echo "$active_connection" | jq -r '.Connection // false')
          ssid=$(echo "$active_connection" | jq -r '.SSID // empty')

          if [ "$connected" = "false" ] || [ -z "$ssid" ]; then
              icon="${wifi-0-icon}"
          fi
          echo "{
              \"connected\": \"$connected\",
              \"ssid\": \"$ssid\",
              \"signal\": \"$signal\",
              \"icon\": \"$icon\"
          }"
      }

      [ "$1" = "get" ] && get && exit
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
      BATTERY_PATH="/sys/class/power_supply/BAT0"
      ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now")
      POWER_NOW=$(cat "$BATTERY_PATH/power_now")
      CAPACITY=$(cat "$BATTERY_PATH/capacity")
      STATUS=$(cat "$BATTERY_PATH/status")

      get() {
          if [ "$POWER_NOW" -eq 0 ]; then
          echo "{
              \"remaining\": { \"hours\": \"0\", \"minutes_total\": \"0\", \"minutes\": \"0\" },
              \"status\": \"$STATUS\",
              \"capacity\": \"$CAPACITY\"
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
              \"remaining\": { \"hours\": \"$HOURS\", \"minutes_total\": \"$MINUTES_TOTAL\", \"minutes\": \"$MINUTES_REMAINDER\" },
              \"status\": \"$STATUS\",
              \"capacity\": \"$CAPACITY\"
          }"
      }

      [ "$1" = "get" ] && get && exit
    '';
  };

  eww-start = pkgs.writeShellApplication {
    name = "eww-start";
    runtimeInputs = [
      pkgs.wlr-randr
      pkgs.jq
    ];
    bashOptions = [ ];
    text = ''
      # Get number of connected displays using wlr-randr
      connected_monitors=$(wlr-randr --json | jq 'length')
      echo Found connected displays: "$connected_monitors"
      # Launch Eww bar on each screen
      ${eww} kill
      ${eww} daemon
      for ((screen=0; screen<connected_monitors; screen++)); do
          echo Starting ewwbar for display $screen
          ${eww} open --no-daemonize --screen "$screen" bar --id bar:$screen --arg screen="$screen"
      done
    '';
  };

  eww-brightness = pkgs.writeShellApplication {
    name = "eww-brightness";
    runtimeInputs = [
      pkgs.gawk
      pkgs.brightnessctl
    ];
    bashOptions = [ ];
    text = ''
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
          ${eww} update brightness="$(get)"
      }

      get() {
          brightness=$(screen_level)
          icon=$(icon "$brightness")
          echo "{
              \"screen\": { \"level\": \"$brightness\" },
              \"icon\": \"$icon\"
          }"
      }

      if [[ "$1" == 'get' ]]; then get; fi
      if [[ "$1" == 'set_screen' ]]; then set_screen "$2"; fi
    '';
  };

  eww-volume = pkgs.writeShellApplication {
    name = "eww-volume";
    runtimeInputs = [
      pkgs.gawk
      audio-ctrl
    ];
    bashOptions = [ ];
    text = ''
      volume_level() {
          audio-ctrl get | awk '{print $1 + 0.0}'
      }

      icon() {
          if [ "$1" -eq 0 ]; then
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
          ${eww} update volume="$(get)"
      }

      get() {
          volume=$(volume_level)
          icon=$(icon "$volume")
          echo "{
              \"level\": \"$volume\",
              \"icon\": \"$icon\"
          }"
      }

      if [[ "$1" == 'get' ]]; then get; fi
      if [[ "$1" == 'set_volume' ]]; then set_volume "$2"; fi
    '';
  };

  eww-power = pkgs.writeShellApplication {
    name = "eww-power";
    runtimeInputs = [ pkgs.givc-cli ];
    bashOptions = [ ];
    text = ''
      # Check if an argument is provided
      if [ $# -ne 1 ]; then
      echo "Usage: $0 {reboot|poweroff|suspend}"
      fi

      # Validate the argument
      case "$1" in (reboot|poweroff|suspend)
          # Call the givc-cli command with the provided argument
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
        (defpoll keyboard_layout :interval "1s" "${pkgs.xorg.setxkbmap}/bin/setxkbmap -query | ${pkgs.gawk}/bin/awk '/layout/{print $2}' | tr a-z A-Z")
        (defpoll time :interval "1s" "date +'%I:%M%p'")
        (defpoll date :interval "1m" "date +'%a %d/%m' | tr a-z A-Z")
        (defpoll calendar_day :interval "10h"
            "date '+%d'")
        (defpoll calendar_month :interval "10h"
            "date '+%-m'")
        (defpoll calendar_year :interval "10h"
            "date '+%Y'")
        (defpoll wifi  :interval "5s" :initial "{}" "${eww-wifi}/bin/eww-wifi get")
        (defpoll battery  :interval "2s" :initial "{}" "${eww-bat}/bin/eww-bat get")
        (defpoll brightness  :interval "1s" :initial "{}" "${eww-brightness}/bin/eww-brightness get")
        (defpoll volume  :interval "1s" :initial "{}" "${eww-volume}/bin/eww-volume get")
        ;; (defpoll bluetooth  :interval "3s" :initial "{}" "${pkgs.bt-launcher}/bin/bt-launcher status")

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							    Widgets        							 ;;	
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Launcher ;;
        (defwidget launcher []
            (button :class "icon_button"
                :onclick "${pkgs.nwg-drawer}/bin/nwg-drawer &"
                (image :path "${launcher-icon}")))

        ;; Generic slider widget ;;
        (defwidget sys_slider [?header icon ?settings-icon level onchange ?onclick ?class ?font-icon ?min] 
        (box :orientation "v"
            :class "qs-slider"
            :spacing 10
            :space-evenly false
            (label :class "header" 
                :visible { header != "" && header != "null" ? "true" : "false" } 
                :text header
                :hexpand true
                :halign "start")
            (box :orientation "h"
                :space-evenly false
                (box :class "icon"
                    :visible {font-icon == "" ? "true" : "false"}
                    :hexpand false
                    :style "background-image: url(\"''${icon}\")")
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
                    :visible { onclick != "" && onclick != "null" ? "true" : "false" }
                    :onclick onclick
                    :class "settings"
                    (box :class "icon"
                        :hexpand false
                        :style "background-image: url(\"''${settings-icon}\")")))
        ))
        (defwidget sys_sliders []
        (box
            :orientation "v"
            :spacing 10
            :hexpand false
            (sys_slider
                    :header "Volume"
                    :icon {volume.icon}
                    :settings-icon "${arrow-right-icon}"
                    :level {volume.level}
                    :onchange "${eww-volume}/bin/eww-volume set_volume {} &")
            (sys_slider
                    :header "Display"
                    :level {brightness.screen.level}
                    :icon {brightness.icon}
                    :min "5"
                    :onchange "${eww-brightness}/bin/eww-brightness set_screen {} &")
        ))
        (defwidget widget_button [icon ?title header ?subtitle ?onclick ?font-icon] 
        (eventbox :class "qs-info-button" :onclick onclick
        (box :orientation "v"
            :class "qs-info-button-padding"
            :spacing 10
            :space-evenly false
            (label :class "title" 
                :visible { title != "" && title != "null" ? "true" : "false" } 
                :text title
                :hexpand true
                :vexpand false
                :halign "start")
            (box :orientation "h"
                :spacing 10
                :valign "center"
                :vexpand "false"
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
                    (label :halign "start" :class "header" :text header)
                    (label :visible {subtitle != "" ? "true" : "false"} :halign "start" :class "subtitle" :text subtitle :limit-width 13))
        ))))
        (defwidget widget_button_small [icon ?onclick ?header] 
        (eventbox :class "qs-info-button-small"
            :onclick onclick
            (box :orientation "h"
                :space-evenly false
                (box :class "icon"
                    :valign "center"
                    :halign "start"
                    :hexpand false
                    :style "background-image: url(\"''${icon}\")")
                (box :class "text"
                    :valign "center"
                    :orientation "v" 
                    :spacing 3
                    :halign "start"
                    :hexpand true
                    (label :halign "start" :class "header" :text header :visible {header != "" ? "true" : "false"}))
        )))
        (defwidget power_menu []
        (box
            :orientation "v"
            :halign "start"
            :hexpand "false"
            :vexpand "false"
            :spacing 10
            :space-evenly "false"
            (widget_button
                    :icon "${power-icon}"
                    :header "Shutdown"
                    :onclick "${eww-popup}/bin/eww-popup power-menu; ${eww-power}/bin/eww-power poweroff")
            (widget_button
                    :icon "${suspend-icon}"
                    :header "Suspend"
                    :onclick "${eww-popup}/bin/eww-popup power-menu; ${eww-power}/bin/eww-power suspend")
            (widget_button
                    :icon "${restart-icon}"
                    :header "Reboot"
                    :onclick "${eww-popup}/bin/eww-popup power-menu; ${eww-power}/bin/eww-power reboot")
        ))
        (defwidget settings_buttons []
        (box
            :orientation "v"
            :spacing 10
            (box
                :orientation "h"
                :space-evenly true
                :spacing 10
                (widget_button
                    :icon {wifi.icon}
                    :header "WiFi"
                    :subtitle {wifi.ssid ?: "Not connected"}
                    :onclick "${eww-popup}/bin/eww-popup quick-settings; ${pkgs.nm-launcher}/bin/nm-launcher &")
                (widget_button
                    :icon "${bluetooth-1-icon}"
                    :header "Bluetooth"
                    :onclick "${eww-popup}/bin/eww-popup quick-settings; ${pkgs.bt-launcher}/bin/bt-launcher &"))
        ))
        (defwidget etc []
        (box :orientation "h"
            :space-evenly true
            :spacing 10
            (widget_button
                :visible { EWW_BATTERY != "" ? "true" : "false" }
                :hexpand true
                :vexpand true
                :subtitle { battery.status == 'Charging' ? "Charging" : 
                            battery.remaining.hours != "0" && battery.remaining.minutes != "0" ? "''${battery.remaining.hours}h ''${battery.remaining.minutes}m" : 
                            battery.remaining.hours == "0" && battery.remaining.minutes != "0" ? "''${battery.remaining.minutes}m" :
                            battery.remaining.hours != "0" && battery.remaining.minutes == "0" ? "''${battery.remaining.hours}h" : 
                            "" }
                :header {EWW_BATTERY != "" ? "''${EWW_BATTERY.BAT0.capacity}%" : "100%"}
                :icon {EWW_BATTERY.BAT0.status == 'Charging' ? "${battery-charging-icon}" :
                        EWW_BATTERY.BAT0.capacity < 10 ? "${battery-0-icon}" :
                            EWW_BATTERY.BAT0.capacity <= 30 ? "${battery-1-icon}" :
                                EWW_BATTERY.BAT0.capacity <= 70 ? "${battery-2-icon}" : "${battery-3-icon}"})
            (box
                :hexpand true
                :vexpand true
                :class "spacer"
            )
        ))
        (defwidget quick-settings-widget []
        (box :class "quick-settings"  
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

        (defwidget power-menu-widget []
        (box :class "quick-settings"  
            :orientation "v"
            :space-evenly false
            (box 
                :class "wrapper_widget"
                :space-evenly false
                :orientation "v"
                (power_menu))))

        (defwidget hotkey_indicator [icon level] 
        (box :class "widget"
            :orientation "h"
            (box :class "icon"
                :style "background-image: url(\"''${icon}\")")
            (box
                :space-evenly false
                :class "percent"
                (label
                    :visible { level != "" && level != "null" ? "true" : "false" }
                    :hexpand true
                    :halign "END"
                    :text "''${level}%"))))

        (defwidget brightness_hotkey_indicator []
        (box :class "hotkey-indicator"
            (hotkey_indicator
                :icon "${security-icon}"
                :level {brightness.screen.level})))
        (defwidget volume_hotkey_indicator []
        (box :class "hotkey-indicator"
            (hotkey_indicator
                :icon "${bluetooth-1-icon}"
                :level {volume?.level})))

        ;; Battery ;;
        (defwidget bat [?capacity ?status ?remaining]
            (tooltip
                (label  :class "tooltip"
                        :text { status == 'Charging' ? "''${status} ''${capacity}%" :
                                status == 'N/A' ? "Battery N/A" :
                                remaining != "" ? "Battery ''${capacity}% (''${remaining})" : "Battery ''${capacity}%" })
                (button :class "icon_button"
                    (image :path { status == 'Charging' ? "${battery-charging-icon}" : status == 'N/A' ? "${battery-charging-icon}" :
                                    capacity < 10 ? "${battery-0-icon}" :
                                        capacity <= 30 ? "${battery-1-icon}" :
                                            capacity <= 70 ? "${battery-2-icon}" : "${battery-3-icon}" }))))
        (defwidget bat-icon-widget [?capacity ?status]
            (image :path { status == 'Charging' ? "${battery-charging-icon}" : status == 'N/A' ? "${battery-charging-icon}" :
                    capacity < 10 ? "${battery-0-icon}" :
                        capacity <= 30 ? "${battery-1-icon}" :
                            capacity <= 70 ? "${battery-2-icon}" : "${battery-3-icon}" }))

        ;; Wifi ;;
        (defwidget wifi []
            (tooltip
            (label  :class "tooltip"
                    :text {wifi.connected != 'false' ? "''${wifi.connected}: ''${wifi.ssid}" : "No connection"})
            (button :class "icon_button"
                    :onclick "${pkgs.nm-launcher}/bin/nm-launcher &"
                    (image :path {wifi.connected == "false" ? "${wifi-0-icon}":
                            "''${wifi.signal ?: -1}" < 0 ? "${wifi-0-icon}" :
                                "''${wifi.signal ?: -1}" < 30 ? "${wifi-1-icon}" :
                                    "''${wifi.signal ?: -1}" < 60 ? "${wifi-2-icon}" :
                                        "''${wifi.signal ?: -1}" < 80 ? "${wifi-3-icon}" : "${wifi-4-icon}"}))))

        ;; Bluetooth ;;
        (defwidget bluetooth []
            (button :class "icon_button"
                (image 
                :path "${bluetooth-1-icon}")))

        ;; Security ;;
        (defwidget security []
            (button :class "icon_button"
                (image 
                :path "${security-icon}")))

        ;; Quick settings button ;;
        (defwidget quick-settings-button [screen wifi-icon bat-icon vol-icon bright-icon]
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
                        :style "background-image: url(\"''${bat-icon}\")")
                    (box :class "icon"
                        :hexpand false
                        :style "background-image: url(\"''${wifi-icon}\")"))))

        ;; Power menu launcher ;;
        (defwidget power-menu-launcher [screen]
            (button :class "icon_button icon" 
                :halign "center" 
                :valign "center" 
                :onclick "${eww-popup}/bin/eww-popup power-menu ''${screen} &"
                (box :class "icon"
                    :hexpand false
                    :style "background-image: url(\"${power-icon}\")")))

        ;; Control Panel Widgets ;;	
        (defwidget control [screen]
            (box :orientation "h" 
                :space-evenly "false" 
                :spacing 14
                :valign "center" 
                :class "control"
                (quick-settings-button :screen screen
                    :bright-icon {brightness.icon}
                    :vol-icon {volume.icon}
                    :wifi-icon {wifi.icon}
                    :bat-icon { EWW_BATTERY.BAT0.status == "Charging" ? "${battery-charging-icon}" : 
                                EWW_BATTERY.BAT0.status == "" ?         "${battery-charging-icon}" :
                                EWW_BATTERY.BAT0.capacity < 10 ?        "${battery-0-icon}" :
                                EWW_BATTERY.BAT0.capacity <= 30 ?       "${battery-1-icon}" :
                                EWW_BATTERY.BAT0.capacity <= 70 ?       "${battery-2-icon}" : 
                                                                        "${battery-3-icon}" }
                    )))

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
                :text time
                :class "time"))

        ;; Date ;;
        (defwidget date [screen]
            (button 
                :onclick "${eww-popup}/bin/eww-popup calendar ''${screen} &"
                :class "icon_button date" date))

        ;; Calendar ;;
        (defwidget cal []
        (eventbox
            :onhoverlost "${eww-popup}/bin/eww-popup calendar &"
            (box :class "cal-box" 
            (box :class "cal-inner-box"
                (calendar :class "cal" 
                    :show-week-numbers false
                    :day calendar_day 
                    :month calendar_month 
                    :year calendar_year)))))

        ;; Left Widgets ;;
        (defwidget left []
            (box	
                :orientation "h" 
                :space-evenly "false" 
                :halign "start" 
                :valign "center" 
                (launcher)))

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
                        :height "46px"
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
        (defwindow volume-hotkey-indicator
            :monitor 0
            :geometry (geometry :y "-200px" 
                                :x "0px"
                                :anchor "center")
            :stacking "overlay"
            (volume_hotkey_indicator))
        (defwindow brightness-hotkey-indicator
            :monitor 0
            :geometry (geometry :y "-200px" 
                                :x "0px"
                                :anchor "center")
            :stacking "overlay"
            (brightness_hotkey_indicator))
      '';

      # The UNIX file mode bits
      mode = "0644";
    };
    # Main eww bar styling
    environment.etc."eww/eww.scss" = {
      text = ''
        * { all: unset; }

        $bg-primary: #121212;
        $widget-bg: #1A1A1A;
        $widget-hover: #282828;

        @mixin unset($rec: false) {
            all: unset;

            @if $rec {
                * {
                    all: unset
                }
            }
        }

        @mixin widget($bg: #161616, $padding: 10px, $radius: 12px){
            border-radius: $radius;
            background-color: $bg;
            padding: $padding;
        }

        @mixin wrapper_widget(){
            @include widget($padding: 14px, $radius: 6px, $bg: $bg-primary);
        }

        @mixin floating_widget($margin: 0em 0.3em 0em 0em){
            @include unset($rec: true);
            border-radius: 6px;
            margin: $margin;

            .wrapper_widget { @include wrapper_widget; }
            box-shadow: 0px 32px 64px 0px rgba(0, 0, 0, 0.24);
        }

        @mixin icon(){
            background-color: transparent;
            background-repeat: no-repeat;
            background-position: center;
            min-height: 24px;
            min-width: 24px;
            font-family: Fira Code;
            font-size: 1.5em;
            color: #FFFFFF;
        }

        @mixin icon-button($bg: transparent, $hover-bg: $widget-hover) {
            @include unset($rec: true);
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

        @mixin slider($slider-width: 225px, $slider-height: 2px, $thumb: true, $thumb-width: 1em, $focusable: true, $radius: 7px, $shadows: true, $trough-bg: #282828) {
            trough {
                border-radius: $radius;
                border: 0;
                background-color: $trough-bg;
                min-height: $slider-height;
                min-width: $slider-width;
                margin: $thumb-width;

                highlight,
                progress {
                    background-color: ${stroke-success};
                    border-radius: $radius;
                }
            }

            slider {
                box-shadow: none;
                background-color: #D3D3D3;
                border: 0 solid transparent;
                border-radius: 50%;
                min-height: $thumb-width;
                min-width: $thumb-width;
                margin: -($thumb-width / 2) 0;
            }

            &:hover {
                slider {
                    @if $thumb {
                        background-color: #D3D3D3;

                        @if $shadows {
                            box-shadow: 0 0 3px 0 $bg-primary;
                        }
                    }
                }
            }

            &:disabled {

                highlight,
                progress {
                    background-color: transparentize(#D3D3D3, 0.4);
                    background-image: none;
                }
            }

            @if $focusable {
                trough:focus {
                    box-shadow: inset 0 0 0 1 $bg-primary;

                    slider {
                        @if $thumb {
                            background-color: red;
                            box-shadow: inset 0 0 0 1 $bg-primary;
                        }
                    }
                }

            }
        }

        @mixin sys-sliders () {
            .slider{ @include slider; }

            .header {
                font-size: 0.8em;
                font-weight: 500;
                font-family: Inter;
            }

            .settings{
                @include icon-button;
                margin-left: 0.15em;

                .icon{
                    @include icon;
                }
            }

            .icon{
                background-color: transparent;
                background-repeat: no-repeat;
                background-position: center;
                min-height: 24px;
                min-width: 24px;
                margin-right: 0.15em;
            }
        }

        @mixin widget-button() {
            @include unset($rec: true);

            border-radius: 50%;
            padding: 0.2em;
            background-color: transparent;
            background-repeat: no-repeat;
            background-position: center;
            min-height: 24px;
            min-width: 24px;

            &:hover {
                transition: 200ms linear background-color;
                background-color: $widget-hover;
            }

            &:disabled {
                background-color: transparentize($widget-hover, 0.4);
                background-image: none;
            }
        }

        @mixin qs-widget($min-height: 70px, $min-width: 150px, $radius: 0.75em, $bg: $widget-bg) {
            min-height: $min-height;
            min-width: $min-width;
            border-radius: $radius;
            background-color: $bg;
        }

        @mixin qs-info-button($min-width: 145px, $radius: 0.75em, $bg: $widget-bg, $padding: 1em, $icon-padding: 0.3em) {
            @include unset($rec: true);
            @include qs-widget ();

            .qs-info-button-padding {
                padding: $padding;
            }

            .title {
                font-size: 0.8em;
                font-weight: 500;
                font-family: Inter;
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
                color: ${text-base};
                font-family: "Inter";
                
                .header {
                    font-weight: 600;
                    font-size: 0.9em;
                }

                .subtitle {
                    font-weight: 400;
                    font-size: 0.7em;
                    min-height: 0px;
                }
            }
        }

        .qs-widget{ @include qs-widget; }

        .wrapper_widget { @include wrapper_widget; }

        .icon { @include icon; }

        .quick-settings{
            @include floating_widget;
        }

        .qs-slider{ 
            @include sys-sliders;
            @include qs-widget;
            padding: 0.625em;
        }

        .hotkey-indicator{
            @include floating_widget($margin: 0);

            .widget{
                @include widget;
            }

            .percent{
                margin-left: 1em;
                min-width: 2.6em;
            }
            
            .icon{
                background-color: $bg-primary;
                background-repeat: no-repeat;
                background-position: center;
                min-height: 24px;
                min-width: 24px;
                margin-right: 1em;

            }
        }

        .widget-button { @include widget-button; }

        .qs-info-button {@include qs-info-button; }

        .qs-info-button-small {
            @include qs-info-button($min-width: 75px, $padding: 0.3em, $icon-padding: 0.1em);
        }

        .eww_bar {
            background-color: $bg-primary;
            padding: 0.2em 1em 0.2em 1em;
            margin-bottom: 0.3em;
        }

        .icon_button {
            @include icon-button;
        }

        .tooltip {
            background-color: $bg-primary;
            color: ${text-base};
            font-family: "Inter";
            font-size: 1em;
            font-weight: ${font-bold};
            padding: 0.25em 0.5em;
            border-radius: 4px;
        }

        .divider {
            background-color: ${icon-subdued};
            padding-left: 1px;
            padding-right: 1px;
            border-radius: 10px;
        }

        .time {
            padding: 0.4em 0.25em;
            border-radius: 0.25em;
            background-color: $bg-primary;
            font-family: "Inter";
            font-weight: ${font-bold};
            font-size: 1em;
            color: ${text-base};
        }

        .date {
            padding: 0.4em 0.25em;
            border-radius: 0.25em;
            font-family: "Inter";
            font-weight: ${font-bold};
            font-size: 1em;
            color: ${text-base};
        }

        .keyboard-layout {
            padding: 0.4em 0.25em;
            border-radius: 4px;
            background-color: $bg-primary;
            font-family: "Inter";
            font-weight: ${font-bold};
            font-size: 1em;
            color: ${text-base};
        }

        .spacer {
            background-color: transparent;
        }

        .cal-box {
            @include floating_widget;
            background-color: $bg-primary;
        }

        .cal {
            font-family: "Inter";
            font-size: 1.2em;
            padding: 0.2em 0.2em;
        }

        .cal-box .cal-inner-box {
            @include wrapper_widget;
        }

        calendar.header {
            color: ${text-base};
            font-weight: ${font-bold};
        }

        calendar:selected {
            color: ${text-success};
        }

        calendar.button {
            color: ${stroke-success};
            padding: 0.3;
            border-radius: 4px;
            border: none;
        }

        calendar.button:hover {
            background-color: ${bg-secondary};
        }

        calendar:indeterminate {
            color: $bg-primary;
        }

      '';

      # The UNIX file mode bits
      mode = "0644";
    };

    systemd.user.services.ewwbar = {
      enable = true;
      description = "ewwbar";
      serviceConfig = {
        Type = "forking";
        ExecStart = "${eww-start}/bin/eww-start";
        Environment = "XDG_CACHE_HOME=/tmp/.ewwcache";
        Restart = "always";
        RestartSec = 1;
      };
      wantedBy = [ "ghaf-session.target" ];
      partOf = [ "ghaf-session.target" ];
    };
  };
}
