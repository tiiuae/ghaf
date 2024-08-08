# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # NOTE: By default networkmanagerapplet and openssh are taken from the same
  #       callPackage set! This means they will be both taken from the same
  #       /nix/store, so it is recommended to override the networkmanagerapplet
  #       with the one from the NetVM.
  networkmanagerapplet,
  openssh,
  writeShellApplication,
  lib,
  uid,
  ...
}:
writeShellApplication {
  name = "nm-launcher";

  text = ''
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ssh_session_dbus.sock
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/ssh_system_dbus.sock
    ${openssh}/bin/ssh -M -S /tmp/control_socket \
        -f -N -q ghaf@net-vm \
        -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o StreamLocalBindUnlink=yes \
        -o ExitOnForwardFailure=yes \
        -L /tmp/ssh_session_dbus.sock:/run/user/${builtins.toString uid}/bus \
        -L /tmp/ssh_system_dbus.sock:/run/dbus/system_bus_socket
    ${networkmanagerapplet}/bin/nm-connection-editor
    # Use the control socket to close the ssh tunnel.
    ${openssh}/bin/ssh -q -S /tmp/control_socket -O exit ghaf@net-vm
  '';

  meta = {
    description = "Script to launch nm-connection-editor to configure network of netvm using D-Bus over SSH.";
    platforms = lib.platforms.linux;
  };
}
