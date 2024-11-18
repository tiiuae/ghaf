# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  blueman,
  bluez,
  openssh,
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
    openssh
    bluez
  ];
  text = ''
    tunnel_name="/tmp/control_socket_bt"
    export PULSE_SERVER=audio-vm:4714

    open-tunnel() {
      local socket_path="$1"
      local remote_user="ghaf"
      local remote_host="audio-vm"
      local local_bind="$2"
      local remote_bind="$3"

      export DBUS_SYSTEM_BUS_ADDRESS=unix:path="$local_bind"
      ssh -M -S "$socket_path" \
          -f -N -q $remote_user@$remote_host \
          -i /run/waypipe-ssh/id_ed25519 \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o StreamLocalBindUnlink=yes \
          -o ExitOnForwardFailure=yes \
          -L "$local_bind:$remote_bind"
    }

    close-tunnel() {
      local socket_path="$1"
      ssh -q -S "$socket_path" -O exit ghaf@audio-vm
    }

    launch-blueman() {
      open-tunnel "$tunnel_name" "/tmp/bt_ssh_system_dbus.sock" "/run/dbus/system_bus_socket"
      blueman-manager
      close-tunnel "$tunnel_name"
    }

    applet() {
      local applet_socket="/tmp/control_socket_bt_applet"
      open-tunnel "$applet_socket" "/tmp/bt_applet_ssh_system_dbus.sock" "/run/dbus/system_bus_socket"
      blueman-applet
      close-tunnel "$applet_socket"
    }

    status() {
      open-tunnel "$tunnel_name" "/tmp/bt_ssh_system_dbus.sock" "/run/dbus/system_bus_socket"
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
      close-tunnel "$tunnel_name"
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
    description = "Script to launch blueman to configure bluetooth of audiovm using D-Bus over SSH.";
    platforms = lib.platforms.linux;
  };
}
