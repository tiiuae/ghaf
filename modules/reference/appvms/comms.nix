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
  inherit (lib) hasAttr optionals mkForce;
in
{
  comms = {
    packages = [
      pkgs.google-chrome
      pkgs.gpsd
    ] ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
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

        ghaf = {
          reference.programs.google-chrome.enable = true;
          xdgitems.enable = true;
          # Disable serial debug console on comms-vm as it makes the serial device owned by
          # 'tty' group. gpsd runs hardcoded with effective gid of 'dialout' group, and thus
          # can't access the device if this is enabled.
          development.usb-serial.enable = mkForce false;
        };

        # Attach GPS receiver to this VM
        microvm.qemu.extraArgs = optionals (
          config.ghaf.hardware.usb.external.enable
          && (hasAttr "gps0" config.ghaf.hardware.usb.external.qemuExtraArgs)
        ) config.ghaf.hardware.usb.external.qemuExtraArgs.gps0;

        # GPSD collects data from GPS and makes it available on TCP port 2947
        services.gpsd = {
          enable = true;
          # Give the ttyUSB0 device for gpsd in case gps was plugged in from boot
          # This doesn't affect anything if device is not available
          devices = [ "/dev/ttyUSB0" ];
          # Use safer read-only mode
          readonly = true;
          # Set debug level to zero so gpsd won't flood the logs unnecessarily
          debugLevel = 0;
          # Listen on all IP-addresses
          listenany = true;
          # Do not wait for a client to connect before polling
          nowait = true;
          # Give gpsd the control socket to use, so it will keep running even if there are no gps devices connected
          extraArgs = [
            "-F"
            "/var/run/gpsd.sock"
          ];
        };
        services.udev.extraRules =
          let
            gps = lib.filter (d: d.name == "gps0") config.ghaf.hardware.definition.usb.external;
          in
          if gps != [ ] then
            let
              VID = (builtins.head gps).vendorId;
              PID = (builtins.head gps).productId;
            in
            # When USB gps device is inserted run gpsdctl to add the device to gpsd, so it starts monitoring it
            # (Note that this will be run way before gpsd service is running, if device is already connected when booting.
            # This does not seem to have any negative effects though)
            ''
              ACTION=="add", ENV{ID_BUS}=="usb", ENV{ID_VENDOR_ID}=="${VID}", ENV{ID_MODEL_ID}=="${PID}", ENV{DEVNAME}=="/dev/ttyUSB*", RUN+="${pkgs.gpsd}/bin/gpsdctl add '%E{DEVNAME}'"
            ''
          else
            '''';
      }
    ];
  };
}
