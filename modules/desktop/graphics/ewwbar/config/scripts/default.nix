# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
        ENERGY_NOW=$([ -d "$BATTERY_PATH" ] && cat "$BATTERY_PATH/energy_now" || echo 0)
        POWER_NOW=$([ -d "$BATTERY_PATH" ] && cat "$BATTERY_PATH/power_now" || echo 0)
        CAPACITY=$([ -d "$BATTERY_PATH" ] && cat "$BATTERY_PATH/capacity" || echo 0)
        STATUS=$([ -d "$BATTERY_PATH" ] && cat "$BATTERY_PATH/status" || echo 0)
        if (( POWER_NOW == 0 )); then
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
        if (( HOURS == 0  &&  MINUTES == 0 )); then
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
      pkgs.bc
      pkgs.bash
      pkgs.gawk
      pkgs.xorg.setxkbmap
    ];
    bashOptions = [ ];
    text = ''
      start() {
        # Get the number of connected displays using wlr-randr and parse the output with jq

        if ! wlr_randr_output=$(wlr-randr --json); then
          echo "Error: Failed to get display info from wlr-randr"
          exit 1
        fi
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

        open-bars "$wlr_randr_output"
      }

      # EWW can only perform integer scaling by default
      # Therefore we need to calculate the expected scaled width in pixels
      open-bars() {
        local wlr_randr_output=$1
        echo "$wlr_randr_output" | jq -c --unbuffered '.[] | select(.enabled == true)' | while read -r display; do
          scale=$(echo "$display" | jq -r '.scale')
          display_name=$(echo "$display" | jq -r '.model')
          width=$(echo "$display" | jq -r '.modes[] | select(.current == true) | .width')
          #scaled_width=$(printf "%.2f" "$(echo "(2 / $scale) * 100" | bc -l)")
          scaled_width=$(echo "$width / $scale" | bc -l | cut -d'.' -f1)
          ${ewwCmd} open --force-wayland --no-daemonize --screen "$display_name" bar --id bar:"$display_name" --arg screen="$display_name" --arg width="$scaled_width"
          ${ewwCmd} open --force-wayland --no-daemonize --screen "$display_name" window-manager-trigger --id window-manager-trigger:"$display_name" --arg screen="$display_name"
        done
      }

      # Reloads current config without opening new windows
      reload() {
        #${ewwCmd} reload
        ${ewwCmd} close-all
        if ! wlr_randr_output=$(wlr-randr --json); then
          echo "Error: Failed to get display info from wlr-randr"
          exit 1
        fi

        open-bars "$wlr_randr_output"
      }

      update-vars() {
        local audio_output
        local audio_input
        local audio_outputs
        local audio_inputs
        ${lib.optionalString useGivc ''
          audio_output=$(${eww-audio}/bin/eww-audio get_output)
          audio_input=$(${eww-audio}/bin/eww-audio get_input)
          audio_outputs=$(${eww-audio}/bin/eww-audio get_outputs)
          audio_inputs=$(${eww-audio}/bin/eww-audio get_inputs)
        ''}
        brightness=$(${eww-brightness}/bin/eww-brightness get)
        battery=$(${eww-bat}/bin/eww-bat get)
        windows=$(${eww-windows}/bin/eww-windows list)
        keyboard_layout=$(setxkbmap -query | awk '/layout/{print $2}' | tr '[:lower:]' '[:upper:]')
        workspace=$(${pkgs.ghaf-workspace}/bin/ghaf-workspace cur)
        if ! [[ $workspace =~ ^[0-9]+$ ]] ; then
            workspace="1"
        fi

        ${ewwCmd} update \
          audio_output="$audio_output" \
          audio_input="$audio_input" \
          audio_outputs="$audio_outputs" \
          audio_inputs="$audio_inputs" \
          brightness="$brightness" \
          battery="$battery" \
          keyboard_layout="$keyboard_layout" \
          windows="$windows" \
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
            )
          }
          catch halt
        ' || echo "{}"
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
              is_muted: (.mute // false),
              device_type: (.active_port as $active_port | .ports[] | select(.name == $active_port).type // "")
            }
          )
          catch halt
        ' || echo "{}"
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
              is_muted: (.mute // false),
              device_type: (.active_port as $active_port | .ports[] | select(.name == $active_port).type // "")
            }
          )
          catch halt
        ' || echo "{}"
      }

      get_sink_inputs() {
        jq -n -c --unbuffered \
          --argjson sink_inputs "$(pactl -f json list sink-inputs)" '
          try (
            [
              $sink_inputs? // [] | map({
                id:  (.index // -1),
                name: (.properties."application.name" // ""),
                icon_name: (.properties."application.icon_name" // ""),
                volume_percentage: ((.volume."front-left".value_percent | sub("%$"; "")) // "0"),
                is_muted: (.mute // false)
              })
            ]
          ) catch halt
        ' || echo "[]"
      }

      get_outputs() {
        jq -n -c --unbuffered \
          --argjson sinks "$(pactl -f json list sinks)" \
          --arg output "$(pactl -f json get-default-sink)" '
          try (
            [
              $sinks[]
              | select(.properties."device.class" != "monitor")
              | {
                  id: (.index // -1),
                  device_name: (.name // ""),
                  is_default: ((.name == $output) // false),
                  volume_percentage: (
                    (.volume | to_entries | first | .value.value_percent | sub("%$"; "") | tonumber) // 0
                  ),
                  state: (.state // ""),
                  friendly_name: (.description // ""),
                  is_muted: (.mute // false),
                  device_type: (.active_port as $active_port | .ports[] | select(.name == $active_port).type // "")
                }
            ]
          ) catch halt
        ' || echo "[]"
      }

      get_inputs() {
        jq -n -c --unbuffered \
          --argjson sources "$(pactl -f json list sources)" \
          --arg input "$(pactl -f json get-default-source)" '
          try (
            [
              $sources[]
              | select(.properties."device.class" != "monitor")
              | {
                  id: (.index // -1),
                  device_name: (.name // ""),
                  is_default: ((.name == $input) // false),
                  volume_percentage: (
                    (.volume | to_entries | first | .value.value_percent | sub("%$"; "") | tonumber) // 0
                  ),
                  state: (.state // ""),
                  friendly_name: (.description // ""),
                  is_muted: (.mute // false),
                  device_type: (.active_port as $active_port | .ports[] | select(.name == $active_port).type // "")
                }
            ]
          ) catch halt
        ' || echo "[]"
      }

      sinkInputs="[]"

      update_sinkInputs() {
          id=$1
          type=$2
          name=$3
          volume=$4
          isMuted=$5
          isDefault=$6
          event=$7

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

      listen_vms() {
        # Subscribing should send an initial list of available resources, so we start listening before subscribing is done
        (sleep 1; dbus-send --session --dest=org.ghaf.Audio --type=method_call --print-reply /org/ghaf/Audio org.ghaf.Audio.SubscribeToDeviceUpdatedSignal > /dev/null 2>&1) &
        dbus-monitor --session "type='signal',interface='org.ghaf.Audio',member='DeviceUpdated'" | \
        awk '
        /^signal/ {
            # If we were already capturing, output the previous signal
            # Start capturing a new signal
            capture = 1;
            id = type = name = volume = isMuted = isDefault = event = "";
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
            # Parse boolean values in order: isMuted, isDefault
            if (isMuted == "") isMuted = $2;
            else if (isDefault == "") isDefault = $2;
        }
        !capture {
            if (type == 4) print id, type, name, volume, isMuted, isDefault, event; fflush(stdout);
        }
        ' | while read -r id type name volume isMuted isDefault event; do
            # Update the JSON array based on the extracted values
            update_sinkInputs "$id" "$type" "$name" "$volume" "$isMuted" "$isDefault" "$event"
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
        get_outputs)
          get_outputs
          ;;
        get_inputs)
          get_inputs
          ;;
        get_sink_inputs)
          get_sink_inputs
          ;;
        set_volume)
          pamixer --unmute --set-volume "$2"
          ;;
        set_sink_input_volume)
          pactl set-sink-input-mute "$2" 0
          pactl set-sink-input-volume "$2" "$3"%
          ;;
        set_vm_volume)
          dbus-send --session --dest=org.ghaf.Audio --type=method_call /org/ghaf/Audio org.ghaf.Audio.SetDeviceVolume int32:"$2" int32:4 int32:"$3"
          ;;
        set_source_volume)
          pamixer --source "$2" --unmute --set-volume "$3"
          ;;
        set_default_source)
          pactl set-default-source "$2"
          ;;
        set_default_sink)
          pactl set-default-sink "$2"
          ;;
        mute)
          pamixer --toggle-mute
          ;;
        mute_vm)
          dbus-send --session --dest=org.ghaf.Audio --type=method_call /org/ghaf/Audio org.ghaf.Audio.SetDeviceMute int32:"$2" int32:4 boolean:"$3"
          ;;
        mute_source)
          pamixer --source "$2" --toggle-mute
          ;;
        mute_sink_input)
          pactl set-sink-input-mute "$2" toggle
          ;;
        listen)
          pactl subscribe | grep --line-buffered "change" | while read -r event; do
            get
          done
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
        listen_outputs)
          pactl subscribe | while read -r event; do
            get_outputs
          done
          ;;
        listen_inputs)
          pactl subscribe | while read -r event; do
            get_inputs
          done
          ;;
        listen_vms)
          listen_vms
          ;;
        *)
          echo "Usage: $0 {get|get_output|get_input|get_outputs|get_inputs|set_volume|set_sink_input_volume|set_source_volume|set_default_source|set_default_sink|mute|mute_source|mute_sink_input|listen_output|listen_input|listen_outputs|listen_inputs|listen_vms} [args...]"
          ;;
      esac
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
        #${ewwCmd} close "$1" closer &
        ${ewwCmd} close "$1" &
        exit 0
      fi

      # Close all windows except the target
      for window in "''${windows[@]}"; do
        if [[ "$window" != "$1" && "$active_windows" == *"$window"* ]]; then
          ${ewwCmd} close "$window" &
        fi
      done

      #${ewwCmd} open-many closer "$1" --arg screen="$2" --arg closer:window="$1"
      ${ewwCmd} open "$1" --screen "$2"
    '';
  };

  eww-fullscreen-update = pkgs.writeShellApplication {
    name = "eww-fullscreen-update";
    runtimeInputs = [
      pkgs.wlrctl
      pkgs.systemd
    ];
    bashOptions = [ ];
    text = ''

            echo "Waiting for a window to enter fullscreen mode..."
            last_fullscreen_state=1

            while true; do
         # Run `wlrctl toplevel find state:fullscreen` and capture the return code
      wlrctl toplevel find state:fullscreen
      current_fullscreen_state=$?

        # If a fullscreen window is detected, and the state has changed
      if [[ $current_fullscreen_state -eq 0 && $last_fullscreen_state -ne 0 ]]; then
          echo "Fullscreen window detected!"
          systemctl --user reload ewwbar
          last_fullscreen_state=0  # Update the state to fullscreen
      elif [[ $current_fullscreen_state -ne 0 && $last_fullscreen_state -eq 0 ]]; then
          # If fullscreen window is no longer detected
          echo "Fullscreen window exited!"
          last_fullscreen_state=1  # Update the state to no fullscreen
      fi

            # Small delay to avoid excessive CPU usage
            sleep 1
          done
    '';
  };

  eww-windows = pkgs.writeShellApplication {
    name = "eww-windows";
    runtimeInputs = [
      pkgs.wlrctl
      pkgs.waylevel
      pkgs.lswt
      pkgs.jq
    ];
    bashOptions = [ ];
    text = ''
      WINDOW_LIST_CMD="waylevel -j"
      FOCUS_CMD="wlrctl window focus"
      CLOSE_CMD="wlrctl window close"

      get_window_list() {
          eval "$WINDOW_LIST_CMD" 2>/dev/null | jq -c --unbuffered 'try ([.[] | {
              app_id: .app_id,
              title: .title,
              state: .state,
              icon: (
                (if .app_id then .app_id | ascii_downcase else "" end) as $id |
                if $id | test("zoom") then "Zoom"
                elif $id | test("slack") then "slack"
                elif $id | test("teams") then "teams-for-linux"
                elif $id | test("outlook") then "ms-outlook"
                elif $id | test("microsoft365") then "microsoft-365"
                elif $id | test("blueman") then "bluetooth-48"
                elif $id | test("ghafaudiocontrol") then "preferences-sound"
                elif $id | test("pcmanfm") then "system-file-manager"
                elif $id | test("losslesscut") then "losslesscut"
                elif $id | test("gpclient") then "yast-vpn"
                elif $id | test("dev.scpp.saca.gala") then "distributor-logo-android"
                elif $id | test("controlpanel") then "utilities-tweak-tool"
                else .app_id end
              )
          }] | unique_by(.app_id)) catch halt' || echo "[]"
      }

      listen() {
          stdbuf -oL lswt -w | grep --line-buffered -E "created|destroyed" | while read -r _; do
              get_window_list
          done
      }

      focus() {
          if [ -z "$1" ]; then
              echo "Usage: $0 focus <window_name>"
              exit 1
          fi
          eval "$FOCUS_CMD '$1' state:-focused"
      }

      close() {
          if [ -z "$1" ]; then
              echo "Usage: $0 close <window_name>"
              exit 1
          fi
          eval "$CLOSE_CMD '$1'"
      }

      case "$1" in
          listen)
              listen
              ;;
          focus)
              focus "$2"
              ;;
          close)
              close "$2"
              ;;
          list)
              get_window_list
              ;;
          *)
              echo "Usage: $0 {listen|focus <window_name>|list}"
              exit 1
              ;;
      esac
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
    eww-open-widget
    eww-windows
    eww-fullscreen-update
    ;
}
