# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  networkmanager,
  openssh,
  util-linux,
  gawk,
  coreutils-full,
  writeShellApplication,
  wifiDevice,
  ...
}:
writeShellApplication {
  name = "wifi-signal-strength";
  runtimeInputs = [
    networkmanager
    openssh
    gawk
    util-linux
    coreutils-full
  ];
  text = ''
    NETWORK_STATUS_FILE=/tmp/network-status

    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ssh_session_dbus.sock
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/ssh_system_dbus.sock

    # Lock the script to reuse
    LOCK_FILE=/tmp/wifi-signal.lock
    exec 99>"$LOCK_FILE"
    flock -w 60 -x 99 || exit 1

    # Return the result as json format for waybar and use the control socket to close the ssh tunnel.
    trap 'ssh -q -S /tmp/nmcli_socket -O exit ghaf@net-vm && cat "$NETWORK_STATUS_FILE"' EXIT

    # Connect to netvm
    ssh -M -S /tmp/nmcli_socket \
        -f -N -q ghaf@net-vm \
        -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o StreamLocalBindUnlink=yes \
        -o ExitOnForwardFailure=yes \
        -L /tmp/ssh_session_dbus.sock:/run/user/1000/bus \
        -L /tmp/ssh_system_dbus.sock:/run/dbus/system_bus_socket
    signal0="\UF091F"
    signal1="\UF0922"
    signal2="\UF0925"
    signal3="\UF0928"
    no_signal="\UF092D"
    # Get IP address of netvm
    address=$(nmcli device show ${wifiDevice} | awk '{ if ($1=="IP4.ADDRESS[1]:") {print $2}}')
    # Get signal strength and ssi
    mapfile -t connection < <(nmcli -f IN-USE,SIGNAL,SSID dev wifi | awk '/^\*/{if (NR!=1) {print $2; print $3}}')
    connection[0]=$(if [ -z "''${connection[0]}" ]; then echo "-1"; else echo "''${connection[0]}"; fi)
    # Set the icon of signal level
    signal_level=$(if [ "''${connection[0]}" -gt 80 ]; then echo "''${signal3}"; elif [ "''${connection[0]}" -gt 60 ]; then echo "''${signal2}"; elif [ "''${connection[0]}" -gt 30 ]; then echo "''${signal1}"; elif [ "''${connection[0]}" -gt 0 ]; then echo "''${signal0};" else echo "''${no_signal}"; fi)
    tooltip=$(if [ -z "''${address}" ]; then echo "''${connection[0]}%"; else echo "''${address} ''${connection[0]}%"; fi)
    text=$(if [ -z "''${connection[1]}" ]; then echo "No connection"; else echo "''${connection[1]} $signal_level"; fi)
    # Save the result in json format
    RESULT="{\"percentage\":\"''${connection[0]}\", \"text\":\"''${text}\", \"tooltip\":\"''${tooltip}\", \"class\":\"1\"}"
    echo -e "$RESULT">/tmp/network-status
    flock -u 99
  '';
}
