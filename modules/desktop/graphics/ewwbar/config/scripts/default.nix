# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  lib,
  useGivc,
  pulseaudioTcpControlPort,
  ghaf-workspace,
  ...
}:

let
  ewwCmd = "${pkgs.eww}/bin/eww -c /etc/eww";

  eww-bat = pkgs.writeShellApplication {
    name = "eww-bat";
    runtimeInputs = [
      pkgs.gawk
      pkgs.bc
    ];
    bashOptions = [ ];
    text = ''
      get() {
        BATTERY_PATH="/sys/class/power_supply/BAT0"
        ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now")
        POWER_NOW=$(cat "$BATTERY_PATH/power_now")
        CAPACITY=$(cat "$BATTERY_PATH/capacity")
        STATUS=$(cat "$BATTERY_PATH/status")
        if [ "$POWER_NOW" -eq 0 ]; then
            echo "{
                \"hours\": \"0\",
                \"minutes_total\": \"0\",
                \"minutes\": \"0\",
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
            \"hours\": \"$HOURS\",
            \"minutes_total\": \"$MINUTES_TOTAL\",
            \"minutes\": \"$MINUTES_REMAINDER\",
            \"status\": \"$STATUS\",
            \"capacity\": \"$CAPACITY\"
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
      get() {
          brightness=$(brightnessctl info | grep -oP '(?<=\().+?(?=%)' | awk '{print $1 + 0.0}')
          echo "{ \"screen\": { \"level\": \"$brightness\" }}"
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
      pkgs.gnused
      pkgs.jq
    ];
    bashOptions = [ ];
    text = ''
      export PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort}

      get() {
        volume=$(pamixer --get-volume)
        muted=$(pamixer --get-mute)

        sink_inputs_json=$(pactl -f json list sink-inputs | jq -c '
            map({
                level: (.volume."front-left".value_percent // "0" | sub("%$"; "")),
                muted: (.mute // "false"),
                name: (.properties."application.name" // ""),
                icon_name: (.properties."application.icon_name" // ""),
                id: (.index // "-1")
            })
        ' || echo "[]")

        # Output the final JSON
        jq -c --unbuffered -n --argjson sinkInputs "$sink_inputs_json" --arg level "$volume" --arg muted "$muted" '
            {
                system: {
                    level: $level,
                    muted: $muted
                },
                sinkInputs: $sinkInputs
            }
        '
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

  eww-open-widget = pkgs.writeShellApplication {
    name = "eww-open-widget";
    bashOptions = [ ];
    text = ''
      # List of available widgets
      windows=("quick-settings" "power-menu" "calendar")

      # Get the current active windows
      active_windows=$(${ewwCmd} active-windows)

      if [[ "$active_windows" == *"$1"* ]]; then
        ${ewwCmd} close "$1" closer &
        exit 0
      fi

      # Close all windows except the target
      (
        for window in "''${windows[@]}"; do
          if [[ "$window" != "$1" ]]; then
            ${ewwCmd} close "$window" &
          fi
        done
      ) &

      ${ewwCmd} open-many closer "$1" --arg screen="$2" --arg closer:window="$1"
    '';
  };

in
{
  # Export each shell application as a top-level attribute
  inherit
    eww-bat
    ewwbar-ctrl
    eww-brightness
    eww-volume
    eww-display
    eww-open-widget
    ;
}
