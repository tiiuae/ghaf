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
      [
        {
          # The SPKI fingerprint is calculated like this:
          # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
          # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
          name = "Google Chrome";
          description = "Isolated General Browsing";
          packages = [ pkgs.google-chrome ];
          icon = "google-chrome";
          command = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}";
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
              };

              networking = {
                firewall.allowedUDPPorts = config.ghaf.reference.services.chromecast.udpPorts;
                firewall.allowedTCPPorts = config.ghaf.reference.services.chromecast.tcpPorts;
              };
            }
          ];
        }
      ]
      ++ (lib.optionals config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIEnabled [
        (
          let
            mitmWebUIport = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPort;
            idsvmIpAddr = config.ghaf.networking.hosts."ids-vm".ipv4;
          in
          {
            name = "MitmWebUI";
            description = "MitmWebUI";
            packages = [ pkgs.google-chrome ];
            icon = "airvpn";
            command = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs} --app=http://${toString idsvmIpAddr}:${toString mitmWebUIport}";
            extraModules = [
              {
                networking = {
                  firewall.allowedTCPPorts = mitmWebUIport;
                };
              }
            ];
          }
        )
      ]);
    extraModules = [
      {
        # Disable camera for now, because, due to the bug, the camera is not accessable in BusinessVM
        # microvm.qemu.extraArgs = optionals (
        #   config.ghaf.hardware.usb.internal.enable
        #   && (hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
        # ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
        microvm.devices = [ ];
      }
    ];
  };
}
