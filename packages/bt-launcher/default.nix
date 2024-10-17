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
  text = ''
    export PULSE_SERVER=audio-vm:4714
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ssh_session_dbus.sock
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/ssh_system_dbus.sock
    ${openssh}/bin/ssh -M -S /tmp/control_socket_bt \
        -f -N -q ghaf@audio-vm \
        -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o StreamLocalBindUnlink=yes \
        -o ExitOnForwardFailure=yes \
        -L /tmp/ssh_session_dbus.sock:/run/user/1000/bus \
        -L /tmp/ssh_system_dbus.sock:/run/dbus/system_bus_socket
    # Use the control socket to close the ssh tunnel.
    close-tunnel() {
      ${openssh}/bin/ssh -q -S /tmp/control_socket_bt -O exit ghaf@audio-vm
    }

    launch-blueman() {
      ${blueman}/bin/blueman-applet &
      ${blueman}/bin/blueman-manager
      close-tunnel
    }

    status() {
      # Get Bluetooth adapter details using bluetoothctl
      BT_INFO=$(${bluez}/bin/bluetoothctl show)

      # Extract relevant fields
      BT_POWERED=$(echo "$BT_INFO" | grep "Powered:" | ${gawk}/bin/awk '{print $2}')
      BT_DISCOVERABLE=$(echo "$BT_INFO" | grep "Discoverable:" | ${gawk}/bin/awk '{print $2}')
      BT_PAIRABLE=$(echo "$BT_INFO" | grep "Pairable:" | ${gawk}/bin/awk '{print $2}')
      BT_DISCOVERING=$(echo "$BT_INFO" | grep "Discovering:" | ${gawk}/bin/awk '{print $2}')
      BT_ALIAS=$(echo "$BT_INFO" | grep "Alias:" | cut -d' ' -f2-)

      status="{\"powered\":\"$BT_POWERED\",\"discoverable\":\"$BT_DISCOVERABLE\",\"pairable\":\"$BT_PAIRABLE\",\"discovering\":\"$BT_DISCOVERING\",\"alias\":\"$BT_ALIAS\"}"

      echo "$status"
      close-tunnel
    }

    if [ $# -eq 0 ]; then
      launch-blueman
    elif [ "$1" = "status" ]; then
      status
    fi
  '';

  meta = {
    description = "Script to launch blueman to configure bluetooth of audiovm using D-Bus over SSH.";
    platforms = lib.platforms.linux;
  };
}
