# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  #TODO: Move this to a common place
  xdgPdfPort = 1200;
  name = "business";
  
  # use nix-prefetch-url to calculate sha256 checksum
  endpointsFile = pkgs.fetchurl {
    url = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7";
    sha256 = "1zly0g23vray4wg6fjxxdys6zzksbymlzggbg75jxqcf8g9j6xnw";
  };

  generateO365FWScript = pkgs.writeShellScript "generate-o365fw-script" ''
    #!/usr/bin/env bash

    set -euo pipefail

    ENDPOINTS_FILE="${endpointsFile}"

    preprocess_url() {
        local url="$1"
        # Return the URL as-is without any filtering
        echo "$url"
    }

    generate_iptables_rules() {
        echo "# Office 365 Firewall Rules"
        echo

        jq -r '.[] | select(.category == "Optimize" or .category == "Allow" or .category == "Default") | .ips[]?' "$ENDPOINTS_FILE" | sort -u | while read -r ip; do
            if [[ $ip == *":"* ]]; then
                echo "ip6tables -I OUTPUT -d $ip -j ACCEPT"
                echo "ip6tables -I INPUT -d $ip -j ACCEPT"
            else
                echo "iptables -I OUTPUT -d $ip -j ACCEPT"
                echo "iptables -I INPUT -d $ip -j ACCEPT"
            fi
        done

        echo

        jq -r '.[] | select(.category == "Optimize" or .category == "Allow" or .category == "Default") | .urls[]?' "$ENDPOINTS_FILE" | sort -u | while read -r url; do
            processed_url=$(preprocess_url "$url")
            if [[ "$processed_url" != "" ]]; then
                echo "iptables -I OUTPUT -p tcp --dport 80 -m string --string \"$processed_url\" --algo bm -j ACCEPT"
                echo "iptables -I INPUT -p tcp --dport 80 -m string --string \"$processed_url\" --algo bm -j ACCEPT"
                echo "iptables -I OUTPUT -p tcp --dport 443 -m string --string \"$processed_url\" --algo bm -j ACCEPT"
                echo "iptables -I INPUT -p tcp --dport 443 -m string --string \"$processed_url\" --algo bm -j ACCEPT"
            fi
        done
    }

    generate_iptables_rules
  '';

  o365fw = pkgs.runCommand "o365fw" {
    buildInputs = [ pkgs.jq ];
  } ''
    ${generateO365FWScript} > $out 
  '';

in
{
  name = "${name}";
  packages =
    let
      # PDF XDG handler is executed when the user opens a PDF file in the browser
      # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
      xdgPdfItem = pkgs.makeDesktopItem {
        name = "ghaf-pdf";
        desktopName = "Ghaf PDF handler";
        exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
        mimeTypes = [ "application/pdf" ];
      };
      xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
        filepath=$(/run/current-system/sw/bin/realpath "$1")
        echo "Opening $filepath" | systemd-cat -p info
        echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm ${toString xdgPdfPort}
      '';
    in
    [
      pkgs.chromium
      pkgs.pulseaudio
      pkgs.xdg-utils
      xdgPdfItem
      xdgOpenPdf
      pkgs.globalprotect-openconnect
      pkgs.openconnect
      pkgs.nftables
    ];
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:10:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    {
      imports = [ ../programs/chromium.nix ];
      # Enable pulseaudio for Chromium VM
      security.rtkit.enable = true;
      users.extraUsers.ghaf.extraGroups = [
        "audio"
        "video"
      ];

      hardware.pulseaudio = {
        enable = true;
        extraConfig = ''
          load-module module-tunnel-sink-new sink_name=business-speaker server=audio-vm:4713 reconnect_interval_ms=1000
          load-module module-tunnel-source-new source_name=business-mic server=audio-vm:4713 reconnect_interval_ms=1000
        '';
        package = pkgs.pulseaudio-ghaf;
      };

      time.timeZone = config.time.timeZone;

      microvm = {
        qemu.extraArgs = lib.optionals (
          config.ghaf.hardware.usb.internal.enable
          && (lib.hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
        ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
        devices = [ ];
      };

      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "business-vm";
        applications = lib.mkForce ''
          {
            "chromium":     "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}",
            "outlook":      "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://outlook.office.com/mail/ ${config.ghaf.givc.idsExtraArgs}",
            "office":       "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://microsoft365.com ${config.ghaf.givc.idsExtraArgs}",
            "teams":        "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://teams.microsoft.com ${config.ghaf.givc.idsExtraArgs}",
            "gpclient":     "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gpclient -platform wayland"
          }'';
      };

      ghaf.reference.programs.chromium.enable = true;

      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";

      # TODO: Add a way to configure the gpclient
      # also check the openconnect cli options https://discourse.nixos.org/t/globalprotect-vpn/24014/5
      services.globalprotect = {
        enable = true;
        csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
      };


      #Firewall Settings
      networking = {
        firewall.enable = true;
        firewall.extraCommands = 
        '' 
          iptables -F

          ${builtins.readFile o365fw} 
        '' 
           + 
        ''

          add_rule() {
              local ip=$1
              iptables -I OUTPUT -p tcp -d $ip --dport 80 -j ACCEPT
              iptables -I OUTPUT -p tcp -d $ip --dport 443 -j ACCEPT
              iptables -I INPUT -p tcp -s $ip --sport 80 -j ACCEPT
              iptables -I INPUT -p tcp -s $ip --sport 443 -j ACCEPT
          }

          # Allow VPN access.tii.ae and iservice
           add_rule 151.253.154.18
           add_rule 10.161.10.120
   
           # Allow tiiuae.sharepoint.com
           add_rule 52.104.7.53
           add_rule 52.105.255.39
           add_rule 13.107.138.10
           add_rule 13.107.136.10
           add_rule 118.215.84.0/24
           add_rule 104.69.171.0/24
           add_rule 13.107.136.10
           add_rule 23.15.111.0/24

           # Block all other HTTP and HTTPS traffic
           iptables -A OUTPUT -p tcp --dport 80 -j REJECT
           iptables -A OUTPUT -p tcp --dport 443 -j REJECT

        '';
      };
    }
  ];
  borderColor = "#00FF00";
  vtpm.enable = true;
}
