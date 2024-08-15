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
in
{
  name = "business";
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
        filepath=$(realpath "$1")
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
  ramMb = 3072;
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
          load-module module-tunnel-sink sink_name=chromium-speaker server=audio-vm:4713 format=s16le channels=2 rate=48000
          load-module module-tunnel-source source_name=chromium-mic server=audio-vm:4713 format=s16le channels=1 rate=48000

          # Set sink and source default max volume to about 90% (0-65536)
          set-sink-volume chromium-speaker 60000
          set-source-volume chromium-mic 60000
        '';
      };

      time.timeZone = config.time.timeZone;

      microvm = {
        qemu.extraArgs = lib.optionals (
          config.ghaf.hardware.usb.internal.enable
          && (lib.hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
        ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
        devices = [ ];
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
        firewall.extraCommands = ''

          iptables -F
            add_rule() {
              local ip=$1
              iptables -I OUTPUT -p tcp -d $ip --dport 80 -j ACCEPT
              iptables -I OUTPUT -p tcp -d $ip --dport 443 -j ACCEPT
              iptables -I INPUT -p tcp -s $ip --sport 80 -j ACCEPT
              iptables -I INPUT -p tcp -s $ip --sport 443 -j ACCEPT
            }
           # Urls can be found from Source: https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges
           # Allow microsoft365.com
           add_rule 13.107.6.156
           add_rule 13.107.9.156

           # Exchange
           add_rule 13.107.6.152/31
           add_rule 13.107.18.10/31
           add_rule 13.107.128.0/22
           add_rule 23.103.160.0/20
           add_rule 40.96.0.0/13
           add_rule 40.104.0.0/15
           add_rule 52.96.0.0/14
           add_rule 131.253.33.215/32
           add_rule 132.245.0.0/16
           add_rule 150.171.32.0/22
           add_rule 204.79.197.215/32


           # Exchange Online
           add_rule 40.92.0.0/15
           add_rule 40.107.0.0/16
           add_rule 52.100.0.0/14
           add_rule 52.238.78.88/32
           add_rule 104.47.0.0/17


           # Sharepoint
           add_rule 13.107.136.0/22
           add_rule 40.108.128.0/17
           add_rule 52.104.0.0/14
           add_rule 104.146.128.0/17
           add_rule 150.171.40.0/22


           # Common
           add_rule 13.107.6.171/32
           add_rule 13.107.18.15/32
           add_rule 13.107.140.6/32
           add_rule 52.108.0.0/14
           add_rule 52.244.37.168/32
           add_rule 20.20.32.0/19
           add_rule 20.190.128.0/18
           add_rule 20.231.128.0/19
           add_rule 40.126.0.0/18
           add_rule 13.107.6.192/32
           add_rule 13.107.9.192/32
           add_rule 52.108.0.0/14

           # Teams
           add_rule 13.107.64.0/18
           add_rule 52.112.0.0/14
           add_rule 52.122.0.0/15
           add_rule 52.108.0.0/14
           add_rule 52.238.119.141/32
           add_rule 52.244.160.207/32
           add_rule 2.16.234.57
           add_rule 23.56.21.152
           add_rule 23.33.233.129
           add_rule 52.123.0.0/16


           # Allow VPN access.tii.ae only
           add_rule 151.253.154.18

           # To be checked
           # Allow res.cdn.office.net
           add_rule 152.199.21.175
           add_rule 152.199.39.108
           add_rule 2.21.231.0/24
           add_rule 2.20.249.0/24
           add_rule 152.199.0.0/16


           # Allow js.monitor.azure.com
           add_rule 13.107.246.0/24

           # Allow c.s-microsoft.com
           add_rule 23.207.193.242
           add_rule 23.208.213.121
           add_rule 23.208.173.122
           add_rule 23.44.1.243
           add_rule 104.65.229.0/24
           add_rule 23.53.113.0/24
           add_rule 2.19.105.47

           # Allow microsoft.com
           add_rule 20.70.246.20
           add_rule 20.236.44.162
           add_rule 20.76.201.171
           add_rule 20.231.239.246
           add_rule 20.112.250.133
           add_rule 184.25.221.172

           # statics.teams.cdn.office.net
           add_rule 95.101.0.0/16
           add_rule 184.87.193.0/24
           add_rule 23.44.0.0/14
           add_rule 96.16.53.0/24
           add_rule 23.59.80.0/24
           add_rule 23.202.33.0/24
           add_rule 104.73.172.0/24
           add_rule 184.27.123.0/24
           add_rule 2.16.56.0/24
           add_rule 23.219.73.130
           add_rule 104.93.18.174
           add_rule 2.21.225.158
           add_rule 23.45.137.145
           add_rule 23.48.121.167
           add_rule 23.46.197.94
           add_rule 104.80.21.47
           add_rule 23.195.154.8
           add_rule 193.229.113.0/24

           # edge.skype.com for teams
           add_rule 13.107.254.0/24
           add_rule 13.107.3.0/24

           # api.flightproxy.skype.com for teams
           add_rule 98.66.0.0/16
           add_rule 4.208.0.0/16
           add_rule 4.225.208.0/24
           add_rule 4.210.0.0/16
           add_rule 108.141.240.0/24
           add_rule 74.241.0.0/16
           add_rule 20.216.0.0/16
           add_rule 172.211.0.0/16
           add_rule 20.50.217.0/24
           add_rule 68.219.14.0/24
           add_rule 20.107.136.0/24
           add_rule 4.175.191.0/24
           add_rule 98.64.0.0/16

           # Allow tiiuae.sharepoint.com
           add_rule 52.104.7.53
           add_rule 52.105.255.39
           add_rule 13.107.138.10
           add_rule 13.107.136.10
           add_rule 118.215.84.0/24
           add_rule 104.69.171.0/24
           add_rule 13.107.136.10
           add_rule 23.15.111.0/24
           # Allow shell.cdn.office.net
           add_rule 23.50.92.176
           add_rule 23.15.30.57
           add_rule 23.50.187.58
           add_rule 104.73.234.244
           add_rule 104.83.143.131
           # Allow res-1.cdn.office.net
           add_rule 23.52.40.0/24
           add_rule 23.64.122.0/24
           add_rule 2.16.106.0/24
           # Allow publiccdn.sharepointonline.com
           add_rule 23.50.86.117
           add_rule 104.69.168.125
           add_rule 2.16.43.238
           add_rule 23.34.79.0/24
           add_rule 23.39.68.0/24
           # r4.res.office365.com
           add_rule 2.19.97.32
           add_rule 2.22.61.139


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
