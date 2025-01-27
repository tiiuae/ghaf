# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) hasAttr optionals;
in
{
  name = "comms";
  packages = [
    pkgs.google-chrome
    pkgs.gpsd
  ] ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
  macAddress = "02:00:00:03:09:01";
  ramMb = 4096;
  cores = 4;
  borderColor = "#337aff";
  ghafAudio.enable = true;
  applications = [
    {
      name = "Element";
      description = "General Messaging Application";
      packages = [ pkgs.element-desktop ];
      icon = "element-desktop";
      command = "element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
      extraModules = [
        {
          imports = [
            ../programs/element-desktop.nix
          ];
          ghaf.reference.programs.element-desktop.enable = true;
        }
      ];
    }
    {
      name = "Slack";
      description = "Teams Collaboration & Messaging Application";
      icon = "slack";
      command = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.slack.com/client ${config.ghaf.givc.idsExtraArgs}";
    }
    {
      name = "Zoom";
      description = "Zoom Videoconferencing Application";
      icon = "Zoom";
      command = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.zoom.us/wc/home ${config.ghaf.givc.idsExtraArgs}";
    }
  ];
  extraModules = [
    {
      imports = [
        # ../programs/chromium.nix
        ../programs/google-chrome.nix
      ];

      ghaf.reference.programs.google-chrome.enable = true;
      ghaf.services.xdghandlers.enable = true;

      # Attach GPS receiver to this VM
      microvm.qemu.extraArgs = optionals (
        config.ghaf.hardware.usb.external.enable
        && (hasAttr "gps0" config.ghaf.hardware.usb.external.qemuExtraArgs)
      ) config.ghaf.hardware.usb.external.qemuExtraArgs.gps0;

      # GPSD collects data from GPS and makes it available on TCP port 2947
      services.gpsd = {
        enable = true;
        devices = [ "/dev/ttyUSB0" ];
        readonly = true;
        debugLevel = 2;
        listenany = true;
        extraArgs = [ "-n" ]; # Do not wait for a client to connect before polling
      };
    }
  ];
}
