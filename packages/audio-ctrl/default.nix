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

    case "$1" in
      inc)
        # Increase volume by 5%
        pamixer -i 5
        ;;
      dec)
        # Decrease volume by 5%
        pamixer -d 5
        ;;
      mut)
        # Toggle mute
        if [ "$(pamixer --get-mute)" = "false" ]; then
          pamixer -m
        else
          pamixer -u
        fi
        ;;
      get)
        # Get current volume level
        pamixer --get-volume
        ;;
      set)
        # Set volume to a specific level
        if [ -n "$2" ]; then
          pamixer --set-volume "$2"
        fi
        ;;
      *)
        echo "Usage: $0 {inc|dec|mut|get|set <volume>}"
        ;;
    esac
  '';
}
