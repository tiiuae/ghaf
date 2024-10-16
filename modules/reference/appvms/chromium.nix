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
  name = "chromium";
in
{
  name = "${name}";
  packages = [
    pkgs.chromium
  ] ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:05:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    {
      imports = [ ../programs/chromium.nix ];

      time.timeZone = config.time.timeZone;

      # Disable camera for now, because, due to the bug, the camera is not accessable in BusinessVM
      # microvm.qemu.extraArgs = optionals (
      #   config.ghaf.hardware.usb.internal.enable
      #   && (hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
      # ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
      microvm.devices = [ ];

      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "chromium-vm";
        applications = [
          {
            name = "chromium";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}";
            args = [
              "url"
              "flag"
            ];
          }
        ];
      };
      ghaf.reference.programs.chromium.enable = true;
      ghaf.services.xdghandlers.enable = true;
    }
  ];
  borderColor = "#B83232";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
