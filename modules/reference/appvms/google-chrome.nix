# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  chrome = {
    packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
    ramMb = 6144;
    cores = 4;
    borderColor = "#630505";
    ghafAudio.enable = true;
    vtpm.enable = true;
    applications =
      let
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
              ${config.ghaf.givc.idsExtraArgs} "$@"
          '';
        };
      in
      [
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
                reference.programs.google-chrome.enable = true;
                xdgitems.enable = true;
                security.apparmor.enable = true;
                firewall = {
                  allowedUDPPorts = config.ghaf.reference.services.chromecast.udpPorts;
                  allowedTCPPorts = config.ghaf.reference.services.chromecast.tcpPorts;
                };
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
            command = "${lib.getExe chromeWrapper} --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs} --app=http://${toString idsvmIpAddr}:${toString mitmWebUIport}?token=${toString mitmWebUIpswd}";
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
        ghaf.reference.services.wireguard-gui.enable = config.ghaf.reference.services.wireguard-gui;

      }
    ];
  };
}
