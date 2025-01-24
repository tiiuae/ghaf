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
  name = "chromium";
  packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
  ramMb = 6144;
  cores = 4;
  borderColor = "#B83232";
  ghafAudio.enable = true;
  vtpm.enable = true;
  applications = [
    {
      # The SPKI fingerprint is calculated like this:
      # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
      # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
      name = "Chromium";
      description = "Isolated General Browsing";
      packages = [ pkgs.chromium ];
      icon = "chromium";
      command = "chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}";
      givcArgs = [
        "url"
        "flag"
      ];
      extraModules = [
        {
          imports = [ ../programs/chromium.nix ];
          ghaf.reference.programs.chromium.enable = true;
          ghaf.services.xdghandlers.enable = true;
        }
      ];
    }
  ];
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
}
