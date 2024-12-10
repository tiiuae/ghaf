# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
let
  name = "chrome";
  hostsEntries = import ../../common/networking/hosts-entries.nix;
  vmname = name + "-vm";
in
{
  name = "${name}";
  packages = [
    pkgs.google-chrome
  ] ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:11:01";
  internalIP = hostsEntries.ipByName vmname;
  ramMb = 6144;
  cores = 4;
  extraModules = [
    {
      imports = [ ../programs/google-chrome.nix ];

      time.timeZone = config.time.timeZone;

      # Disable camera for now, because, due to the bug, the camera is not accessable in BusinessVM
      # microvm.qemu.extraArgs = optionals (
      #   config.ghaf.hardware.usb.internal.enable
      #   && (hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
      # ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
      microvm.devices = [ ];

      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "chrome-vm";
        applications = [
          {
            name = "google-chrome";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}";
            args = [
              "url"
              "flag"
            ];
          }
        ];
      };
      ghaf.reference.programs.google-chrome.enable = true;
      ghaf.services.xdghandlers.enable = true;
    }
  ];
  borderColor = "#630505";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
