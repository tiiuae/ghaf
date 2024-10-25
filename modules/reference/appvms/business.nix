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
  inherit (lib) mkIf optionalString;
  #TODO: Move this to a common place
  name = "business";
  tiiVpnAddr = "151.253.154.18";
  vpnOnlyAddr = "${tiiVpnAddr},jira.tii.ae,access.tii.ae,confluence.tii.ae,i-service.tii.ae,catalyst.atrc.ae";
  netvmEntry = builtins.filter (x: x.name == "net-vm") config.ghaf.networking.hosts.entries;
  netvmAddress = lib.head (builtins.map (x: x.ip) netvmEntry);
  adminvmEntry = builtins.filter (x: x.name == "admin-vm") config.ghaf.networking.hosts.entries;
  adminvmAddress = lib.head (builtins.map (x: x.ip) adminvmEntry);
  # Remove rounded corners from the text editor window
  gnomeTextEditor = pkgs.gnome-text-editor.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + ''
        echo -e '\nwindow { border-radius: 0px; }' >> src/style.css
      '';
  });
in
{
  name = "${name}";
  packages =
    [
      pkgs.chromium
      pkgs.globalprotect-openconnect
      pkgs.losslesscut-bin
      pkgs.openconnect
      gnomeTextEditor
      pkgs.xarchiver
    ]
    ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ]
    ++ lib.optionals config.ghaf.givc.enable [ pkgs.open-normal-extension ];

  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:10:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    (
      { pkgs, ... }:
      {
        imports = [
          ../programs/chromium.nix
          ../services/globalprotect-vpn/default.nix
        ];
        time.timeZone = config.time.timeZone;

        microvm = {
          qemu.extraArgs = lib.optionals (
            config.ghaf.hardware.usb.internal.enable
            && (lib.hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
          ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
          devices = [ ];
        };

        ghaf = {
          givc.appvm = {
            enable = true;
            name = lib.mkForce "business-vm";
            applications = [
              {
                name = "chromium";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
                args = [ "url" ];
              }
              {
                name = "outlook";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://outlook.office.com/mail/ ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "office";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://microsoft365.com ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "teams";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://teams.microsoft.com ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "gpclient";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gpclient -platform wayland";
              }
              {
                name = "gnome-text-editor";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gnome-text-editor";
              }
              {
                name = "losslesscut";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/losslesscut --enable-features=UseOzonePlatform --ozone-platform=wayland";
              }
              {
                name = "xarchiver";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/xarchiver";
              }
            ];
          };

          reference = {
            programs.chromium.enable = true;

            services.globalprotect = {
              enable = true;
              csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
            };
          };

          services.xdghandlers.enable = true;
        };

        environment.etc."chromium/native-messaging-hosts/fi.ssrc.open_normal.json" =
          mkIf config.ghaf.givc.enable
            {
              source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
            };
        environment.etc."open-normal-extension.cfg" = mkIf config.ghaf.givc.enable {
          text =
            let
              cliArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
                --name ${config.ghaf.givc.adminConfig.name}
                --addr ${config.ghaf.givc.adminConfig.addr}
                --port ${config.ghaf.givc.adminConfig.port}
                ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
                ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/business-vm-cert.pem"}
                ${optionalString config.ghaf.givc.enableTls "--key /run/givc/business-vm-key.pem"}
                ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
              '';
            in
            ''
              export GIVC_PATH="${pkgs.givc-cli}"
              export GIVC_OPTS="${cliArgs}"
            '';
        };

        # Enable dconf and icon pack for gnome text editor
        programs.dconf.enable = true;
        environment.systemPackages = [ pkgs.adwaita-icon-theme ];

        #Firewall Settings
        networking = {
          proxy = {
            default = "http://${netvmAddress}:${toString config.ghaf.reference.services.proxy-server.bindPort}";
            noProxy = "192.168.101.10,${adminvmAddress},127.0.0.1,localhost,${vpnOnlyAddr}";
          };
          firewall = {
            enable = true;
            extraCommands = ''

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
        };
      }
    )
  ];
  borderColor = "#218838";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
