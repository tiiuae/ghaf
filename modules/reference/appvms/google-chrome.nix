# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Google Chrome Browser App VM
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.chrome;

  chromeWrapper = pkgs.writeShellApplication {
    name = "chrome-wrapper";
    runtimeInputs = [
      pkgs.jq
      pkgs.google-chrome
    ];

    text = ''
      PREFS="$HOME/.config/google-chrome/Default/Preferences"
      mkdir -p "$(dirname "$PREFS")"

      # Create a minimal Preferences file if it doesn't exist
      if [ ! -f "$PREFS" ]; then
        echo '{}' > "$PREFS"
      fi

      # Enable system title bar and borders
      jq '
        .browser |= . // {}
        | .browser.custom_chrome_frame = false
      ' "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"

      # Launch the browser
      google-chrome-stable --enable-features=UseOzonePlatform \
        --ozone-platform=wayland \
        --disable-gpu \
        ${config.ghaf.givc.idsExtraArgs} "$@"
    '';
  };
in
{
  _file = ./google-chrome.nix;

  options.ghaf.reference.appvms.chrome = {
    enable = lib.mkEnableOption "Google Chrome Browser App VM";
  };

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.appvm.vms.chrome = {
      enable = lib.mkDefault true;
      name = "chrome";
      borderColor = "#9C0000";

      applications = [
        {
          name = "Google Chrome";
          description = "Isolated General Browsing";
          packages = [
            pkgs.google-chrome
            chromeWrapper
          ];
          icon = "google-chrome";
          command = "chrome-wrapper";
          givcArgs = [
            "url"
            "flag"
          ];
        }
      ]
      ++ (lib.optionals config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIEnabled [
        (
          let
            mitmWebUIport = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPort;
            mitmWebUIpswd = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPswd;
            idsvmIpAddr = config.ghaf.networking.hosts."ids-vm".ipv4;
          in
          {
            name = "MitmWebUI";
            description = "MitmWebUI";
            packages = [ pkgs.google-chrome ];
            icon = "nmap";
            command = "${lib.getExe chromeWrapper} ${config.ghaf.givc.idsExtraArgs} --app=http://${toString idsvmIpAddr}:${toString mitmWebUIport}?token=${toString mitmWebUIpswd}";
          }
        )
      ]);

      vtpm = {
        enable = lib.mkDefault true;
        runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
        basePort = 9150;
      };

      usbPassthrough = [
        {
          description = "External Webcams for ChromeVM and BusinessVM";
          allowedVms = [
            "chrome-vm"
            "business-vm"
          ];
          allow = [
            {
              interfaceClass = 14;
              description = "Video (USB Webcams)";
            }
          ];
          # Ignore internal webcams since they are attached to business-vm
          deny = config.ghaf.reference.passthrough.usb.internalWebcams;
        }
      ];

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "chrome";
        packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
        ramMb = 6144;
        cores = 4;
        borderColor = "#9C0000";
        ghafAudio.enable = lib.mkDefault true;
        vtpm = {
          enable = lib.mkDefault true;
          runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
          basePort = 9150;
        };
        yubiProxy = true;
        applications = [
          {
            # The SPKI fingerprint is calculated like this:
            # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
            # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
            name = "Google Chrome";
            description = "Isolated General Browsing";
            packages = [
              pkgs.google-chrome
              chromeWrapper
            ];
            icon = "google-chrome";
            command = "chrome-wrapper";
            givcArgs = [
              "url"
              "flag"
            ];
            extraModules = [
              {
                imports = [ ../programs/google-chrome.nix ];
                ghaf = {
                  reference.programs.google-chrome.enable = lib.mkDefault true;
                  security.apparmor.enable = lib.mkDefault true;
                  xdgitems = {
                    enable = lib.mkDefault true;
                  };
                  xdghandlers.url = true;
                  firewall = {
                    allowedUDPPorts = config.ghaf.reference.services.chromecast.udpPorts;
                    allowedTCPPorts = config.ghaf.reference.services.chromecast.tcpPorts;
                  };
                  storagevm.maximumSize = 100 * 1024; # 100 GB space for google-chrome-vm
                };
              }
            ];
          }
        ]
        ++ (lib.optionals config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIEnabled [
          (
            let
              mitmWebUIport = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPort;
              mitmWebUIpswd = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPswd;
              idsvmIpAddr = config.ghaf.networking.hosts."ids-vm".ipv4;
            in
            {
              name = "MitmWebUI";
              description = "MitmWebUI";
              packages = [ pkgs.google-chrome ];
              icon = "nmap";
              command = "${lib.getExe chromeWrapper} ${config.ghaf.givc.idsExtraArgs} --app=http://${toString idsvmIpAddr}:${toString mitmWebUIport}?token=${toString mitmWebUIpswd}";
              extraModules = [
                {
                  ghaf.firewall.allowedTCPPorts = mitmWebUIport;
                }
              ];
            }
          )
        ]);
        extraModules = [
          {
            microvm.devices = [ ];
            imports = [
              ../services/wireguard-gui/wireguard-gui.nix
            ];
            # Enable WireGuard GUI
            ghaf.reference.services.wireguard-gui = {
              enable = config.ghaf.reference.services.wireguard-gui;
              serverPorts = [
                51822
              ];
            };
          }
        ];
      };
    };
  };
}
