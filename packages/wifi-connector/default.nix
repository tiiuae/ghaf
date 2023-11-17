# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  ...
}: let
  wifiConnector =
    pkgs.writeShellScript
    "wifi-connector"
    ''
      # Check if the script is run as root
      if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as root or with sudo."
        exit 1
      fi

      # Check if two arguments (SSID and PSK) are provided
      if [ $# -ne 2 ]; then
        echo "Usage: $0 <SSID> <PSK>"
        exit 1
      fi

      SSID="$1"
      PSK="$2"

      # Stop any running wpa_supplicant instances
      pkill wpa_supplicant

      # Create a wpa_supplicant configuration file
      cat > ./wpa_supplicant.conf <<EOL
      network={
          ssid="$SSID"
          psk="$PSK"
      }
      EOL

      # Start wpa_supplicant with the specified configuration
      wpa_supplicant -B -i wlp0s4f0 -c ./wpa_supplicant.conf

      # Wait for a few seconds to allow the connection to establish
      sleep 5

      # Check if the connection was successful
      if ifconfig wlp0s4f0 | grep -q "inet"; then
        echo "Connected to $SSID successfully."
      else
        echo "Failed to connect to $SSID."
      fi
    '';
in
  stdenvNoCC.mkDerivation {
    name = "wifi-connector";

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp ${wifiConnector} $out/bin/wifi-connector
    '';

    meta = with lib; {
      description = "Helper script making Wi-Fi connection easier";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
