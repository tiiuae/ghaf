# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  blueman,
  openssh,
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "bt-launcher";

  text = ''
    export PULSE_SERVER=audio-vm:4713
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
    ${blueman}/bin/blueman-applet &
    ${blueman}/bin/blueman-manager
    # Use the control socket to close the ssh tunnel.
    ${openssh}/bin/ssh -q -S /tmp/control_socket_bt -O exit ghaf@audio-vm
  '';

  meta = {
    description = "Script to launch blueman to configure bluetooth of audiovm using D-Bus over SSH.";
    platforms = lib.platforms.linux;
  };
}
