# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is a temporary solution for volume control.
#
{
  openssh,
  writeShellApplication,
  ...
}:
writeShellApplication {
  name = "audio-ctrl";
  runtimeInputs = [
    openssh
  ];
  text = ''
    function pamixer {
      # Connect to audio-vm
      output=$(ssh -q ghaf@audio-vm \
          -i /run/waypipe-ssh/id_ed25519 \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          "pamixer $1")
    }

    case "$1" in
      inc)
        pamixer "-i 5"
        ;;
      dec)
        pamixer "-d 5"
        ;;
      mut)
        pamixer "--get-mute"
        if [ "$output" = "false" ]; then
          pamixer "-m"
        else
          pamixer "-u"
        fi
        ;;
      esac
  '';
}
