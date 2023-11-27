# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  useNmcli ? false,
  ...
}: let
  wifiConnector =
    pkgs.writeShellScript
    "wifi-connector"
    (''
        # Check if the script is run as root
        if [ "$EUID" -ne 0 ]; then
          echo "Please run this script as root or with sudo."
          exit 1
        fi

        while getopts ":ds:p:" opt; do
          case $opt in
            d)
              echo "Disconnecting..."
      ''
      + lib.optionalString useNmcli ''
              CONNECTION=$(nmcli d | grep -w wifi | grep -w connected |  awk '{print $4}')
              if [ -z "$CONNECTION" ]; then
                echo "No active Wi-Fi connection found";
                exit 0;
              fi
              nmcli con down id $CONNECTION
      ''
      + lib.optionalString (!useNmcli) ''
              #Stop any running wpa_supplicant instances
              pkill wpa_supplicant
      ''
      + ''
              exit 0
              ;;
            s)
              SSID=$OPTARG
              ;;
            p)
              PSK=$OPTARG
              ;;
            \?)
               echo "Invalid option: -$OPTARG" >&2
               exit 1
               ;;
            :)
               echo "Option -$OPTARG does not take an argument." >&2
               exit 1
               ;;
          esac
        done

        if [ -z "$SSID" ] || [ -z "$PSK" ]; then
          echo "Usage: $0 -s <SSID> -p <PSK> OR -d to disconnect"
          exit 1
        fi

      ''
      + lib.optionalString useNmcli ''
        #Run nmcli command, get its output;
        #split above result with ' as a delimiter and take the second part (devicename)
        DEVICE=$(nmcli device wifi connect $SSID password $PSK | cut -d"'" -f2)
      ''
      + lib.optionalString (!useNmcli) ''
        #Stop any running wpa_supplicant instances
        pkill wpa_supplicant

        DEVICE=$(ifconfig | grep wlp | cut -d":" -f1)

        # Create a wpa_supplicant configuration file
        cat > ./wpa_supplicant.conf <<EOL
        network={
            ssid="$SSID"
            psk="$PSK"
        }
        EOL

        # Start wpa_supplicant with the specified configuration
        wpa_supplicant -B -i $DEVICE -c ./wpa_supplicant.conf
      ''
      + ''
        # Wait for a few seconds to allow the connection to establish
        sleep 5

        # Check if the connection was successful
        if ifconfig $DEVICE | grep -q "inet"; then
          echo "Connected to $SSID successfully."
        else
          echo "Failed to connect to $SSID."
        fi
      '');
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
