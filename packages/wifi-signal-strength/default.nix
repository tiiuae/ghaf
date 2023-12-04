# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  wifiDevice,
  ...
}: let
  # Replace the IP address with "net-vm.ghaf" after DNS/DHCP module merge
  netvm_address = "192.168.100.1";
  wifiSignalStrength =
    pkgs.writeShellScript
    "wifi-signal-strength"
    ''
      export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ssh_session_dbus.sock
      export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/ssh_system_dbus.sock
      ${pkgs.openssh}/bin/ssh -M -S /tmp/nmcli_socket \
          -f -N -q ghaf@${netvm_address} \
          -i /run/waypipe-ssh/id_ed25519 \
          -o StrictHostKeyChecking=no \
          -o StreamLocalBindUnlink=yes \
          -o ExitOnForwardFailure=yes \
          -L /tmp/ssh_session_dbus.sock:/run/user/1000/bus \
          -L /tmp/ssh_system_dbus.sock:/run/dbus/system_bus_socket
      signal0=󰤟
      signal1=󰤢
      signal2=󰤥
      signal3=󰤨
      no_signal=󰤭
      # Get IP address of netvm
      address=$(${pkgs.networkmanager}/bin/nmcli device show ${wifiDevice} | ${pkgs.gawk}/bin/awk '{ if ($1=="IP4.ADDRESS[1]:") {print $2}}')
      # Get signal strength and ssid
      connection=($(${pkgs.networkmanager}/bin/nmcli -f IN-USE,SIGNAL,SSID dev wifi | ${pkgs.gawk}/bin/awk '/^\*/{if (NR!=1) {print $2; print $3}}'))
      connection[0]=$(if [ -z ''${connection[0]} ]; then echo "-1"; else echo ''${connection[0]}; fi)
      # Set the icon of signal level
      signal_level=$(if [ ''${connection[0]} -gt 80 ]; then echo $signal3; elif [ ''${connection[0]} -gt 60 ]; then echo $signal2; elif [ ''${connection[0]} -gt 30 ]; then echo $signal1; elif [ ''${connection[0]} -gt 0 ]; then echo signal0; else echo $no_signal; fi)
      tooltip=$(if [ -z ''${connection[1]} ]; then echo "No connection"; else echo ''${connection[1]} ''${connection[0]}%; fi)
      text=$(if [ -z $address ]; then echo $signal_level; else echo $address $signal_level; fi)
      # Return as json format for waybar
      echo "{\"percentage\":\""''${connection[0]}"\", \"text\":\""$text"\", \"tooltip\":\""$tooltip"\", \"class\":\"1\"}"
      # Use the control socket to close the ssh tunnel.
      ${pkgs.openssh}/bin/ssh -q -S /tmp/nmcli_socket -O exit ghaf@${netvm_address}
    '';
in
  stdenvNoCC.mkDerivation {
    name = "wifi-signal-strength";

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp ${wifiSignalStrength} $out/bin/wifi-signal-strength
    '';

    meta = with lib; {
      description = "Script to get wifi data from nmcli to show network of netvm using D-Bus over SSH on Waybar.";
      platforms = [
        "x86_64-linux"
      ];
    };
  }
