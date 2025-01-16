# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs,
  lib,
  useGivc,
  pulseaudioTcpControlPort,
  ...
}:

let
  ewwCmd = "${pkgs.eww}/bin/eww -c /etc/eww";

  ghaf-workspace = pkgs.callPackage ../../../../../../packages/ghaf-workspace { };

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
        ${ewwCmd} daemon --force-wayland 
        update-vars

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
        local audio_output
        local audio_input
        ${lib.optionalString useGivc ''
          audio_output=$(${eww-audio}/bin/eww-audio get_output)
          audio_input=$(${eww-audio}/bin/eww-audio get_input)
        ''}
        brightness=$(${eww-brightness}/bin/eww-brightness get)
        battery=$(${eww-bat}/bin/eww-bat get)
        keyboard_layout=$(setxkbmap -query | awk '/layout/{print $2}' | tr '[:lower:]' '[:upper:]')
        workspace=$(${ghaf-workspace}/bin/ghaf-workspace cur)
        if ! [[ $workspace =~ ^[0-9]+$ ]] ; then
            workspace="1"
        fi

        ${ewwCmd} update \
          audio_output="$audio_output" \
          audio_input="$audio_input" \
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

  eww-audio = pkgs.writeShellApplication {
    name = "eww-audio";
    runtimeInputs = [
      pkgs.gawk
      pkgs.pulseaudio
      pkgs.pamixer
      pkgs.gnused
      pkgs.jq
      pkgs.dbus
    ];
    bashOptions = [ ];
    text = ''
      export PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort}

      get() {
        jq -n -c --unbuffered \
          --argjson sinks "$(pactl -f json list sinks)" \
          --argjson sources "$(pactl -f json list sources)" \
          --argjson sink_inputs "$(pactl -f json list sink-inputs)" \
          --arg output "$(pactl -f json get-default-sink)" \
          --arg input "$(pactl -f json get-default-source)" '
          try
          {
            output_device: (
              $sinks[] | select(.name == $output) | {
                device_name: ($output // ""),
                device_index: (.index // -1),
                friendly_name: (.description // ""),
                port_description: (.ports[0].description // ""),
                state: (.state // ""),
                volume_percentage: (
                  (.volume | to_entries | first | .value.value_percent | sub("%$"; "")) // "0"
                ),
                is_muted: (.mute // false)
              }
            ),
            input_device: (
              $sources[] | select(.name == $input) | {
                device_name: ($input // ""),
                device_index: (.index // -1),
                friendly_name: (.description // ""),
                port_description: (.ports[0].description // ""),
                state: (.state // ""),
                volume_percentage: (
                  (.volume | to_entries | first | .value.value_percent | sub("%$"; "")) // "0"
                ),
                is_muted: (.mute // false)
              }
            ),
            audio_streams: (
              $sink_inputs? // [] | map({
                id:  .index,
                name: .properties."application.name",
                icon_name: .properties."application.icon_name",
                volume_percentage: (.volume."front-left".value_percent | sub("%$"; "")),
                is_muted: .mute
              })
            )
          }
          catch halt
        '
      }

      get_output() {
        jq -n -c --unbuffered \
          --argjson sinks "$(pactl -f json list sinks)" \
          --arg output "$(pactl -f json get-default-sink)" '
          try
          (
            $sinks[] | select(.name == $output) | {
              device_name: ($output // ""),
              device_index: (.index // -1),
              friendly_name: (.description // ""),
              port_description: (.ports[0].description // ""),
              state: (.state // ""),
              volume_percentage: (
                (.volume | to_entries | first | .value.value_percent | sub("%$"; "")) // "0"
              ),
              is_muted: (.mute // false)
            }
          )
          catch halt
        '
      }

      get_input() {
        jq -n -c --unbuffered \
          --argjson sources "$(pactl -f json list sources)" \
          --arg input "$(pactl -f json get-default-source)" '
          try
          (
            $sources[] | select(.name == $input) | {
              device_name: ($input // ""),
              device_index: (.index // -1),
              friendly_name: (.description // ""),
              port_description: (.ports[0].description // ""),
              state: (.state // ""),
              volume_percentage: (
                (.volume | to_entries | first | .value.value_percent | sub("%$"; "")) // "0"
              ),
              is_muted: (.mute // false)
            }
          )
          catch halt
        '
      }

      sinkInputs="[]"

      update_sinkInputs() {
          local id=$1
          local type=$2
          local name=$3
          local volume=$4
          local isMuted=$5
          local event=$6

          case $event in
              0) # Add object
                  if ! echo "$sinkInputs" | jq -e ".[] | select(.id == $id)" > /dev/null; then
                      sinkInputs=$(echo "$sinkInputs" | jq -c --unbuffered ". + [{\"id\": $id, \"type\": $type, \"name\": \"$name\", \"level\": $volume, \"icon_name\": \"\", \"muted\": $isMuted, \"event\": $event}]")
                  fi
                  ;;
              1) # Update object or add if it doesn't exist
                  if echo "$sinkInputs" | jq -e ".[] | select(.id == $id)" > /dev/null; then
                      sinkInputs=$(echo "$sinkInputs" | jq -c --unbuffered "map(if .id == $id then . + {\"type\": $type, \"name\": \"$name\", \"level\": $volume, \"icon_name\": \"\", \"muted\": $isMuted, \"event\": $event} else . end)")
                  else
                      sinkInputs=$(echo "$sinkInputs" | jq -c --unbuffered ". + [{\"id\": $id, \"type\": $type, \"name\": \"$name\", \"level\": $volume, \"icon_name\": \"\", \"muted\": $isMuted, \"event\": $event}]")
                  fi
                  ;;
              2) # Remove object
                  sinkInputs=$(echo "$sinkInputs" | jq -c --unbuffered "del(.[] | select(.id == $id))")
                  ;;
          esac
      }

      listen_sink_inputs() {
        dbus-monitor --session "type='signal',interface='org.ghaf.Audio',member='DeviceUpdated'" | \
        awk '
        /^signal/ {
            # If we were already capturing, output the previous signal
            # Start capturing a new signal
            capture = 1;
            id = type = name = volume = isMuted = event = "";
        }
        /int32/ && capture {
            # Parse int32 values in order: id, type, volume, event
            if (id == "") id = $2;
            else if (type == "") type = $2;
            else if (volume == "") volume = $2;
            else if (event == "") {event = $2; capture = 0;}
        }
        /string/ && capture {
            # Parse string value (name)
            match($0, /"([^"]*)"/, arr);
            if (arr[1] != "") name = arr[1];
        }
        /boolean/ && capture {
            # Parse boolean value (isMuted)
            isMuted = $2;
        }
        !capture {
            if (type == 2) print id, type, name, volume, isMuted, event; fflush(stdout);
        }
        ' | while read -r id type name volume isMuted event; do
            # Update the JSON array based on the extracted values
            update_sinkInputs "$id" "$type" "$name" "$volume" "$isMuted" "$event"
            # Print the updated JSON array
            echo "$sinkInputs"
        done
      }

      case "$1" in
        get)
          get
          ;;
        get_output)
          get_output
          ;;
        get_input)
          get_input
          ;;
        set_volume)
          pamixer --unmute --set-volume "$2"
          ;;
        set_sink_input_volume)
          pactl set-sink-input-mute "$2" 0
          pactl set-sink-input-volume "$2" "$3"% 
          ;;
        set_source_volume)
          pamixer --source "$2" --unmute --set-volume "$3"
          ;;
        mute)
          pamixer --toggle-mute
          ;;
        mute_source)
          pamixer --source "$2" --toggle-mute
          ;;
        mute_sink_input)
          pactl set-sink-input-mute "$2" toggle
          ;;
        listen_output)
          pactl subscribe | grep --line-buffered "change" | while read -r event; do
            get_output
          done
          ;;
        listen_input)
          pactl subscribe | grep --line-buffered "change" | while read -r event; do
            get_input
          done
          ;;
        listen_sink_inputs)
          listen_sink_inputs
          ;;
        *)
          echo "Usage: $0 {get|set_volume|mute|listen|listen_sink_inputs} [args...]"
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
      for window in "''${windows[@]}"; do
        if [[ "$window" != "$1" ]]; then
          ${ewwCmd} close "$window" &
        fi
      done

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
    eww-audio
    eww-display
    eww-open-widget
    ;
}
