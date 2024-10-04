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
  tiiVpnAddr = "151.253.154.18";
  vpnOnlyAddr = "${tiiVpnAddr},jira.tii.ae,access.tii.ae,confluence.tii.ae,i-service.tii.ae,catalyst.atrc.ae";
  netvmEntry = builtins.filter (x: x.name == "net-vm") config.ghaf.networking.hosts.entries;
  netvmAddress = lib.head (builtins.map (x: x.ip) netvmEntry);
  adminvmEntry = builtins.filter (x: x.name == "admin-vm") config.ghaf.networking.hosts.entries;
  adminvmAddress = lib.head (builtins.map (x: x.ip) adminvmEntry);
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
      pkgs.xdg-utils
      xdgPdfItem
      xdgOpenPdf
      pkgs.globalprotect-openconnect
      pkgs.losslesscut-bin
      pkgs.openconnect
      pkgs.gnome-text-editor
    ]
    ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];

  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:10:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    {
      imports = [ ../programs/chromium.nix ];
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
            "chromium":              "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}",
            "outlook":               "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://outlook.office.com/mail/ ${config.ghaf.givc.idsExtraArgs}",
            "office":                "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://microsoft365.com ${config.ghaf.givc.idsExtraArgs}",
            "teams":                 "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://teams.microsoft.com ${config.ghaf.givc.idsExtraArgs}",
            "gpclient":              "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gpclient -platform wayland",
            "gnome-text-editor":     "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gnome-text-editor",
            "losslesscut":           "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/losslesscut --enable-features=UseOzonePlatform --ozone-platform=wayland"
          }'';
      };

      ghaf.reference.programs.chromium.enable = true;
      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";

      # Enable printer service
      ghaf.services.printer = {
        enable = true;
        name = "${name}";
      };

      # TODO: Add a way to configure the gpclient
      # also check the openconnect cli options https://discourse.nixos.org/t/globalprotect-vpn/24014/5
      services.globalprotect = {
        enable = true;
        csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
      };

      # Enable dconf and icon pack for gnome text editor
      programs.dconf.enable = true;
      environment.systemPackages = [ pkgs.gnome.adwaita-icon-theme ];

      #Firewall Settings
      networking = {
        firewall.enable = true;
        proxy = {
          default = "http://${netvmAddress}:${toString config.ghaf.reference.services.proxy-server.bindPort}";
          noProxy = "192.168.101.10,${adminvmAddress},127.0.0.1,localhost,${vpnOnlyAddr}";
        };
        firewall.extraCommands = ''

          add_rule() {
                local ip=$1
                iptables -I OUTPUT -p tcp -d $ip --dport 80 -j ACCEPT
                iptables -I OUTPUT -p tcp -d $ip --dport 443 -j ACCEPT
                iptables -I INPUT -p tcp -s $ip --sport 80 -j ACCEPT
                iptables -I INPUT -p tcp -s $ip --sport 443 -j ACCEPT
              }
          # Default policy 
          iptables -P INPUT DROP

          # Block any other unwanted traffic (optional)
          iptables -N logreject
          iptables -A logreject -j LOG
          iptables -A logreject -j REJECT

          # allow everything for local VPN traffic
          iptables -A INPUT -i tun0 -j ACCEPT
          iptables -A FORWARD -i tun0 -j ACCEPT
          iptables -A FORWARD -o tun0 -j ACCEPT
          iptables -A OUTPUT -o tun0 -j ACCEPT

          # WARN: if all the traffic including VPN flowing through proxy is intended,
          # remove "add_rule 151.253.154.18" rule and pass "--proxy-server=http://192.168.100.1:3128" to openconnect(VPN) app.
          # also remove "151.253.154.18,tii.ae,.tii.ae,sapsf.com,.sapsf.com" addresses from noProxy option and add
          # them to allow acl list in modules/reference/appvms/3proxy-config.nix file.
          # Allow VPN access.tii.ae 
          add_rule ${tiiVpnAddr}

          # Block all other HTTP and HTTPS traffic
          iptables -A OUTPUT -p tcp --dport 80 -j logreject
          iptables -A OUTPUT -p tcp --dport 443 -j logreject
          iptables -A OUTPUT -p udp --dport 80 -j logreject
          iptables -A OUTPUT -p udp --dport 443 -j logreject

        '';
      };
    }
  ];
  borderColor = "#00FF00";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
