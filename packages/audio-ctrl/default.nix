# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is a temporary solution for volume control.
#
{ pamixer, writeShellApplication, ... }:
writeShellApplication {
  name = "audio-ctrl";
  runtimeInputs = [ pamixer ];
  text = ''
    export PULSE_SERVER=audio-vm:4713

    unmute() {
      if [[ "$(pamixer --get-mute)" == "true" ]]; then
          pamixer -t
      fi
    }

    case "$1" in
      inc)
        # Unmute if muted
        unmute
        # Increase volume by 5%
        pamixer -i 5
        ;;
      dec)
        # Unmute if muted
        unmute
        # Decrease volume by 5%
        pamixer -d 5
        ;;
      mut)
        # Toggle mute
        pamixer -t
        ;;
      get_mut)
        pamixer --get-mute
        ;;
      get)
        # Get current volume level
        pamixer --get-volume
        ;;
      set)
        # Set volume to a specific level
        if [ -n "$2" ]; then
          # Unmute if muted
          if [[ "$(pamixer --get-mute)" == "true" ]]; then
              pamixer -t
          fi
          pamixer --set-volume "$2"
        fi
        ;;
      *)
        echo "Usage: $0 {inc|dec|mut|get|set <volume>}"
        ;;
    esac
  '';
}
