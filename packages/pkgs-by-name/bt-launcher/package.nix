# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  blueman,
  bluez,
  writeShellApplication,
  gawk,
  lib,
  ...
}:
writeShellApplication {
  name = "bt-launcher";
  runtimeInputs = [
    gawk
    blueman
    bluez
  ];
  text = ''
    export PULSE_SERVER=audio-vm:4714
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock

    launch-blueman() {
      blueman-manager
    }

    applet() {
      blueman-applet
    }

    status() {
      # Get Bluetooth adapter details using bluetoothctl
      BT_INFO=$(bluetoothctl show)

      # Extract relevant fields
      BT_POWERED=$(echo "$BT_INFO" | grep "Powered:" | awk '{print $2}')
      BT_DISCOVERABLE=$(echo "$BT_INFO" | grep "Discoverable:" | awk '{print $2}')
      BT_PAIRABLE=$(echo "$BT_INFO" | grep "Pairable:" | awk '{print $2}')
      BT_DISCOVERING=$(echo "$BT_INFO" | grep "Discovering:" | awk '{print $2}')
      BT_ALIAS=$(echo "$BT_INFO" | grep "Alias:" | cut -d' ' -f2-)

      status="{\"powered\":\"$BT_POWERED\",\"discoverable\":\"$BT_DISCOVERABLE\",\"pairable\":\"$BT_PAIRABLE\",\"discovering\":\"$BT_DISCOVERING\",\"alias\":\"$BT_ALIAS\"}"

      echo "$status"
    }

    if [ $# -eq 0 ]; then
      launch-blueman
    fi

    case "$1" in
      status)
        status
        ;;
      applet)
        applet
        ;;
      close)
        applet
        ;;
      *)
        echo "Unknown option"
        ;;
    esac
  '';

  meta = {
    description = "Script to launch blueman to configure bluetooth of audiovm using D-Bus via GIVC.";
    platforms = lib.platforms.linux;
  };
}
