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
        pamixer -i 5
        ;;
      dec)
        pamixer -d 5
        ;;
      mut)
        if [ "$(pamixer --get-mute)" = "false" ]; then
          pamixer -m
        else
          pamixer -u
        fi
        ;;
      esac
  '';
}
