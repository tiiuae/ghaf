# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  lib,
  ...
}:
{
  business = {
    packages = lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
    ramMb = 6144;
    cores = 4;
    borderColor = "#218838";
    ghafAudio.enable = true;
    vtpm.enable = true;
    applications =
      let
        inherit (config.microvm.vms."business-vm".config.config.ghaf.reference.services.pac) proxyPacUrl;
        browserCommand = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension} --proxy-pac-url=${proxyPacUrl}";
      in
      [
        {
          name = "Trusted Browser";
          description = "Isolated Trusted Browsing";
          packages = [ pkgs.google-chrome ];
          icon = "thorium-browser";
          command = browserCommand;
          givcArgs = [
            "url"
          ];
          extraModules = [
            {
              imports = [
                #../programs/chromium.nix
                ../programs/google-chrome.nix
              ];

              ghaf = {
                reference = {
                  programs.google-chrome = {
                    enable = true;
                    openInNormalExtension = true;
                  };
                };

                xdgitems.enable = true;
                security.apparmor.enable = true;
              };
            }
          ];
        }
        {
          name = "Microsoft Outlook";
          description = "Microsoft Email Client";
          icon = "ms-outlook";
          command = "${browserCommand} --app=https://outlook.office.com/mail/";
        }
        {
          name = "Microsoft 365";
          description = "Microsoft 365 Software Suite";
          icon = "microsoft-365";
          command = "${browserCommand} --app=https://microsoft365.com";
        }
        {
          name = "Teams";
          description = "Microsoft Teams Collaboration Application";
          icon = "teams-for-linux";
          command = "${browserCommand} --app=https://teams.microsoft.com";
        }
        {
          name = "VPN";
          description = "GlobalProtect VPN Client";
          packages = [
            pkgs.globalprotect-openconnect
            pkgs.openconnect
          ];
          icon = "yast-vpn";
          command = "gpclient -platform wayland";
          extraModules = [
            {
              imports = [
                ../services/globalprotect-vpn/default.nix
              ];

              ghaf.reference.services.globalprotect = {
                enable = true;
                csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
              };
            }
          ];
        }
        {
          name = "Video Editor";
          description = "Losslesscut Video Editor";
          packages = [ pkgs.losslesscut-bin ];
          icon = "losslesscut";
          command = "losslesscut --enable-features=UseOzonePlatform --ozone-platform=wayland";
        }
      ]
      ++ lib.optionals (config.ghaf.profiles.graphics.compositor != "cosmic") [
        {
          name = "Text Editor";
          description = "Simple Text Editor";
          packages =
            let
              # Remove rounded corners from the text editor window
              gnomeTextEditor = pkgs.gnome-text-editor.overrideAttrs (oldAttrs: {
                postPatch = (oldAttrs.postPatch or "") + ''
                  echo -e '\nwindow { border-radius: 0px; }' >> src/style.css
                '';
              });
            in
            [
              gnomeTextEditor
              pkgs.adwaita-icon-theme
            ];
          icon = "org.gnome.TextEditor";
          command = "gnome-text-editor";
          extraModules = [
            {
              # Enable dconf for gnome text editor
              programs.dconf.enable = true;
            }
          ];
        }
        {
          name = "Xarchiver";
          description = "File Compressor";
          packages = [ pkgs.xarchiver ];
          icon = "xarchiver";
          command = "xarchiver";
        }
      ];
    extraModules = [

      {
        # Attach integrated camera to this vm
        microvm.devices = [ ];
        imports = [
          ../services/pac/pac.nix
          ../services/firewall/firewall.nix
          ../services/wireguard-gui/wireguard-gui.nix
        ];

        # Enable Proxy Auto-Configuration service for the browser
        ghaf.reference.services = {
          pac = {
            enable = true;
            proxyAddress = config.ghaf.reference.services.proxy-server.internalAddress;
            proxyPort = config.ghaf.reference.services.proxy-server.bindPort;
          };

          # Enable firewall and allow access to TII VPN
          firewall.enable = true;

          # Enable WireGuard GUI
          wireguard-gui.enable = config.ghaf.reference.services.wireguard-gui;

        };
      }
    ];
  };
}
