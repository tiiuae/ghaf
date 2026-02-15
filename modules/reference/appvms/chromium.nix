# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Chromium Browser App VM
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.chromium;
in
{
  _file = ./chromium.nix;

  options.ghaf.reference.appvms.chromium = {
    enable = lib.mkEnableOption "Chromium Browser App VM";
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable and evaluatedConfig at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.chromium = {
      enable = lib.mkDefault false;

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "chromium";
        packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
        mem = 6144;
        vcpu = 4;
        borderColor = "#9C0000";
        ghafAudio.enable = lib.mkDefault true;
        vtpm = {
          enable = lib.mkDefault true;
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
                  reference.programs.chromium.enable = lib.mkDefault true;
                  xdgitems = {
                    enable = lib.mkDefault true;
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
    };
  };
}
