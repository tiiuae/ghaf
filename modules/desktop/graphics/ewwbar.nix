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

  launcher-icon = "${pkgs.ghaf-artwork}/icons/launcher.svg";
  battery-0-icon = "${pkgs.ghaf-artwork}/icons/battery-empty.svg";
  battery-1-icon = "${pkgs.ghaf-artwork}/icons/battery-almost-empty.svg";
  battery-2-icon = "${pkgs.ghaf-artwork}/icons/battery-half.svg";
  battery-3-icon = "${pkgs.ghaf-artwork}/icons/battery-full.svg";
  battery-charging-icon = "${pkgs.ghaf-artwork}/icons/battery-charging.svg";
  bluetooth-icon = "${pkgs.ghaf-artwork}/icons/bluetooth.svg";
  wifi-0-icon = "${pkgs.ghaf-artwork}/icons/wifi-0.svg";
  wifi-1-icon = "${pkgs.ghaf-artwork}/icons/wifi-1.svg";
  wifi-2-icon = "${pkgs.ghaf-artwork}/icons/wifi-2.svg";
  wifi-3-icon = "${pkgs.ghaf-artwork}/icons/wifi-3.svg";
  wifi-4-icon = "${pkgs.ghaf-artwork}/icons/wifi-green.svg";
  security-icon = "${pkgs.ghaf-artwork}/icons/security-green.svg";

  # Colors
  ## Background
  bg-primary = "#121212";
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

  ewwPopup = pkgs.writeShellScript "popup" ''
    calendar() {
        LOCK_FILE="$HOME/.cache/eww-calendar.lock"

        run() {
            # Update day, month and year before opening the calendar
            ${eww} update calendar_day=$(date +%d)
            ${eww} update calendar_month=$(date +%-m)
            ${eww} update calendar_year=$(date +%Y)
            ${eww} open --screen $1 calendar --logs
        }

        # Open widgets
        if [[ ! -f "$LOCK_FILE" ]]; then
            touch "$LOCK_FILE"
            run $1
        else
            ${eww} close calendar
            rm "$LOCK_FILE"
        fi
    }

    if [ "$1" = "wifi" ]; then
        ${pkgs.nm-launcher}/bin/nm-launcher
    elif [ "$1" = "calendar" ]; then
        calendar $2
    fi

  '';

  ewwWifi = pkgs.writeShellScript "wifi" ''
    grpcurl_cmd_get_active_connection="${pkgs.grpcurl}/bin/grpcurl -plaintext 192.168.100.1:9000 wifimanager.WifiService.GetActiveConnection"

    signal() {
        signal_level=$(echo "$1" | ${pkgs.jq}/bin/jq '.Signal // empty')
        echo $signal_level
    }

    status() {
        active_connection=$($grpcurl_cmd_get_active_connection)
        ${eww} update wifi-signal-level=$(signal "$active_connection")

        connected=$(echo "$active_connection" | ${pkgs.jq}/bin/jq -r '.Connection // false')
        ssid=$(echo "$active_connection" | ${pkgs.jq}/bin/jq -r '.SSID // empty')
        if [ "$connected" = "false" ] || [ -z "$ssid" ]; then
            echo No connection
        else
            ${eww} update wifi-name=$ssid
            echo Connected
        fi
    }

    [ "$1" = "status" ] && status && exit
    [ "$1" = "signal" ] && signal && exit
  '';

  ewwBat = pkgs.writeShellScript "battery" ''
    BATTERY_PATH="/sys/class/power_supply/BAT0"
    ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now")
    POWER_NOW=$(cat "$BATTERY_PATH/power_now")

    remaining() {
        if [ "$POWER_NOW" -eq 0 ]; then
            echo ""
        fi

        TIME_REMAINING=$(echo "scale=2; $ENERGY_NOW / $POWER_NOW" | ${pkgs.bc}/bin/bc )

        HOURS=$(echo "$TIME_REMAINING" | ${pkgs.gawk}/bin/awk '{print int($1)}')
        MINUTES=$(echo "($TIME_REMAINING - $HOURS) * 60" | ${pkgs.bc}/bin/bc | ${pkgs.gawk}/bin/awk '{printf "%d\n", $1}')
        
        # If both hours and minutes are 0, return an empty string
        if [ "$HOURS" -eq 0 ] && [ "$MINUTES" -eq 0 ]; then
            echo ""
        else
            # Display remaining time in shorthand
            if [ "$HOURS" -gt 0 ] && [ "$MINUTES" -gt 0 ]; then
                echo "''${HOURS}h ''${MINUTES}m"
            elif [ "$HOURS" -gt 0 ]; then
                echo "''${HOURS}h"
            else
                echo "''${MINUTES}m"
            fi
        fi
    }

    [ "$1" = "remaining" ] && remaining && exit
  '';

  ewwStart = pkgs.writeShellScript "ewwStart" ''
    # Get number of connected displays using wlr-randr
    connected_monitors=$(${pkgs.wlr-randr}/bin/wlr-randr --json | ${pkgs.jq}/bin/jq 'length')
    echo Found connected displays: $connected_monitors
    # Launch Eww bar on each screen
    ${eww} kill
    ${eww} daemon
    for ((screen=0; screen<$connected_monitors; screen++)); do
        echo Starting ewwbar for display $screen
        ${eww} open --no-daemonize --screen $screen bar --id bar:$screen --arg screen=$screen
    done
  '';

in
{
  config = lib.mkIf cfg.enable {
    # Main eww bar config
    environment.etc."eww/eww.yuck" = {
      text = ''
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							   Variables        					     ;;	
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        (defvar wifi-signal-level 0)
        (defvar wifi-name "N/A")
        (defpoll wifi-status 
            :interval "5s"
            :initial "N/A"
            "${ewwWifi} status")
        (defpoll battery-remaining 
            :interval "5s"
            :initial ""
            "${ewwBat} remaining")
        (defpoll keyboard_layout :interval "1s" "${pkgs.xorg.setxkbmap}/bin/setxkbmap -query | ${pkgs.gawk}/bin/awk '/layout/{print $2}' | tr a-z A-Z")
        (defpoll time :interval "1s" "date +'%I:%M%p'")
        (defpoll date :interval "1m" "date +'%a %d/%m' | tr a-z A-Z")
        (defpoll calendar_day :interval "10h"
            "date '+%d'")
        (defpoll calendar_month :interval "10h"
            "date '+%-m'")
        (defpoll calendar_year :interval "10h"
            "date '+%Y'")

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;							    Widgets        							 ;;	
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Launcher ;;
        (defwidget launcher []
            (button :class "taskbar_button"
                :onclick "${pkgs.nwg-drawer}/bin/nwg-drawer &"
                (image :path "${launcher-icon}")))

        ;; Battery ;;
        (defwidget bat [?capacity ?status ?remaining]
            (tooltip
                (label  :class "tooltip"
                        :text { status == 'Charging' ? "''${status} ''${capacity}%" :
                                status == 'N/A' ? "Battery N/A" :
                                remaining != "" ? "Battery ''${capacity}% (''${remaining})" : "Battery ''${capacity}%" })
                (button :class "taskbar_button"
                    (image :path { status == 'Charging' ? "${battery-charging-icon}" : status == 'N/A' ? "${battery-charging-icon}" :
                                    capacity < 10 ? "${battery-0-icon}" :
                                        capacity <= 30 ? "${battery-1-icon}" :
                                            capacity <= 70 ? "${battery-2-icon}" : "${battery-3-icon}" }))))

        ;; Wifi ;;
        (defwidget wifi []
            (tooltip
            (label  :class "tooltip"
                    :text {wifi-status != 'No connection' ? "''${wifi-status}: ''${wifi-name}" : "No connection"})
            (button :class "taskbar_button"
                    :onclick "${ewwPopup} wifi &"
                    (image :path {wifi-status == 'No connection' ? "${wifi-0-icon}":
                            "''${wifi-signal-level ?: -1}" < 0 ? "${wifi-0-icon}" :
                                "''${wifi-signal-level ?: -1}" < 30 ? "${wifi-1-icon}" :
                                    "''${wifi-signal-level ?: -1}" < 60 ? "${wifi-2-icon}" :
                                        "''${wifi-signal-level ?: -1}" < 80 ? "${wifi-3-icon}" : "${wifi-4-icon}"}))))

        ;; Bluetooth ;;
        (defwidget bluetooth []
            (button :class "taskbar_button"
                (image 
                :path "${bluetooth-icon}")))

        ;; Security ;;
        (defwidget security []
            (button :class "taskbar_button"
                (image 
                :path "${security-icon}")))

        ;; Control Panel Widgets ;;	
        (defwidget control []
            (box :orientation "h" 
                :space-evenly "false" 
                :spacing 14
                :valign "center" 
                :class "control"
                (bat    :status {EWW_BATTERY != "" ? EWW_BATTERY.BAT0.status : "N/A"}
                        :capacity {EWW_BATTERY != "" ? EWW_BATTERY.BAT0.capacity : "100"}
                        :remaining battery-remaining)
                (wifi)))

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
                :onclick "${ewwPopup} calendar ''${screen} &"
                :class "taskbar_button"
                (label
                    :text date
                    :class "date")))

        ;; Calendar ;;
        (defwidget cal []
        (eventbox
            :onhoverlost "${ewwPopup} calendar &"
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
        (defwidget right [screen]
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
                (control)
                (divider)
                (right :screen screen)))

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
                        :height "4%"
                        :width "100%" 
                        :anchor "bottom center")
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
                                :height "15%" 
                                :width "16%"
                                :anchor "bottom right")
            :stacking "fg"
            (cal))

      '';

      # The UNIX file mode bits
      mode = "0644";
    };
    # Main eww bar styling
    environment.etc."eww/eww.css" = {
      text = ''
        * { all: unset; }

        .eww_bar {
            background-color: ${bg-primary};
            padding: 0.3em 1.25em 0.3em 1.25em;
            border-radius: 4px;
            margin: 0.3em 1.25em 1.25em 1.25em;
        }

        .taskbar_button {
            border-radius: 0.25em;
            padding: 0.3em;
            background-color: ${bg-primary};
            background-repeat: no-repeat;
            background-position: center;
        }

        .wifi_0_icon {
            background-image: url('${wifi-0-icon}');
        }

        .wifi_1_icon {
            background-image: url('${wifi-1-icon}');
        }

        .wifi_2_icon {
            background-image: url('${wifi-2-icon}');
        }

        .wifi_3_icon {
            background-image: url('${wifi-3-icon}');
        }

        .wifi_4_icon {
            background-image: url('${wifi-4-icon}');
        }

        .taskbar_button:hover {
            transition: 200ms linear background-color;
            background-color: ${bg-secondary};
        }

        .tooltip {
            background-color: ${bg-primary};
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
            background-color: ${bg-primary};
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
            background-color: ${bg-primary};
            font-family: "Inter";
            font-weight: ${font-bold};
            font-size: 1em;
            color: ${text-base};
        }

        .cal-box {
            margin: 0 1.25em 0 1.25em;
            background-color: ${bg-primary};
            padding: 0px;
            border-radius: 4px;
        }

        .cal {
            font-family: "Inter";
            font-size: 1.2em;
            padding: 0.2em 0.2em;
        }

        .cal-box .cal-inner-box {
            padding: 0px;
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
            color: ${bg-primary};
        }

      '';

      # The UNIX file mode bits
      mode = "0644";
    };
    # Start eww bar as a service, --logs needed to prevent shutdown (investigation needed)
    systemd.user.services.ewwbar = {
      enable = true;
      description = "ewwbar";
      serviceConfig = {
        Type = "forking";
        ExecStart = "${ewwStart}";
        Environment = "XDG_CACHE_HOME=/tmp/.ewwcache";
        Restart = "always";
        RestartSec = 5;
      };
      wantedBy = [ "ghaf-session.target" ];
      partOf = [ "ghaf-session.target" ];
    };
  };
}
