# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  chromium = {
    packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
    ramMb = 6144;
    cores = 4;
    borderColor = "#9C0000";
    ghafAudio.enable = true;
    vtpm = {
      enable = true;
      runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
      basePort = 9120;
    };
    yubiProxy = true;
    applications = [
      {
        # The SPKI fingerprint is calculated like this:
        # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
        # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
        name = "Chromium";
        description = "Isolated General Browsing";
        packages = [ pkgs.chromium ];
        icon = "chromium";
        command = "chromium --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}";
        givcArgs = [
          "url"
          "flag"
        ];
        extraModules = [
          {
            imports = [ ../programs/chromium.nix ];

            ghaf = {
              reference.programs.chromium.enable = true;
              xdgitems = {
                enable = true;
              };
              xdghandlers.url = true;

              storagevm.maximumSize = 100 * 1024; # 100 GB space for chrome-vm

              firewall = {
                allowedUDPPorts = config.ghaf.reference.services.chromecast.udpPorts;
                allowedTCPPorts = config.ghaf.reference.services.chromecast.tcpPorts;
              };
            };
          }
        ];
      }
    ];
    extraModules = [
      {
        microvm.devices = [ ];
      }
    ];
  };
}
