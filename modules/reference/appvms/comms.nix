# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Communications App VM - Element, Slack, Zoom
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.comms;
in
{
  _file = ./comms.nix;

  options.ghaf.reference.appvms.comms = {
    enable = lib.mkEnableOption "Communications App VM";
  };

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.appvm.vms.comms = {
      enable = lib.mkDefault true;
      name = "comms";
      borderColor = "#337aff";

      applications = [
        {
          name = "Element";
          description = "General Messaging Application";
          packages = [ pkgs.element-desktop ];
          icon = "element-desktop";
          command = "element-desktop --enable-logging --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland";
        }
        {
          name = "Slack";
          description = "Teams Collaboration & Messaging Application";
          icon = "slack";
          command = "google-chrome-stable --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.slack.com/client ${config.ghaf.givc.idsExtraArgs}";
        }
        {
          name = "Zoom";
          description = "Zoom Videoconferencing Application";
          icon = "Zoom";
          command = "google-chrome-stable --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.zoom.us/wc/home ${config.ghaf.givc.idsExtraArgs}";
        }
      ];

      vtpm = {
        enable = lib.mkDefault true;
        runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
        basePort = 9130;
      };

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "comms";
        packages = [
          pkgs.google-chrome
          pkgs.gpsd
        ]
        ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
        ramMb = 4096;
        cores = 4;
        borderColor = "#337aff";
        ghafAudio.enable = lib.mkDefault true;
        vtpm = {
          enable = lib.mkDefault true;
          runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
          basePort = 9130;
        };
        applications = [
          {
            name = "Element";
            description = "General Messaging Application";
            packages = [ pkgs.element-desktop ];
            icon = "element-desktop";
            command = "element-desktop --enable-logging --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland";
            extraModules = [
              {
                imports = [
                  ../programs/element-desktop.nix
                ];
                ghaf.reference.programs.element-desktop.enable = lib.mkDefault true;
                ghaf.xdghandlers.elementDesktop = true;
                ghaf.xdgitems.elementDesktop = true;
              }
            ];
          }
          {
            name = "Slack";
            description = "Teams Collaboration & Messaging Application";
            icon = "slack";
            command = "google-chrome-stable --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.slack.com/client ${config.ghaf.givc.idsExtraArgs}";
          }
          {
            name = "Zoom";
            description = "Zoom Videoconferencing Application";
            icon = "Zoom";
            command = "google-chrome-stable --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.zoom.us/wc/home ${config.ghaf.givc.idsExtraArgs}";
          }
        ];
        extraModules = [
          {
            imports = [
              ../programs/google-chrome.nix
            ];

            ghaf = {
              reference.programs.google-chrome.enable = lib.mkDefault true;
              # Open external URLs locally in comms-vm's browser instead of forwarding to a dedicated URL-handling VM
              xdghandlers.url = true;
              xdgitems.enable = lib.mkDefault true;
              # Disable serial debug console on comms-vm as it makes the serial device owned by
              # 'tty' group. gpsd runs hardcoded with effective gid of 'dialout' group, and thus
              # can't access the device if this is enabled.
              development.usb-serial.enable = lib.mkForce false;
              storagevm.maximumSize = 100 * 1024; # 100 GB space for comms-vm
            };

            # GPSD collects data from GPS and makes it available on TCP port 2947
            services.gpsd = {
              enable = lib.mkDefault true;
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
          }
        ];
      };
    };
  };
}
