# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  inherit (config.ghaf.hardware.definition.network) pciDevices;
  inherit (import ../../../lib/icons.nix {inherit pkgs lib;}) svgToPNG;

  launchpad-icon = svgToPNG "launchpad" ../../../assets/icons/svg/launchpad.svg "38x38";
  admin-icon = svgToPNG "admin" ../../../assets/icons/svg/admin-cog.svg "24x24";
  ghaf-icon = svgToPNG "ghaf-white" ../../../assets/icons/svg/ghaf-white.svg "24x24";

  wifiDevice = lib.lists.findFirst (d: d.name != null) null pciDevices;
  wifi-signal-strength = pkgs.callPackage ../../../packages/wifi-signal-strength {wifiDevice = wifiDevice.name;};
  ghaf-launcher = pkgs.callPackage ./ghaf-launcher.nix {inherit config pkgs;};
  timeZone =
    if config.time.timeZone != null
    then config.time.timeZone
    else "UTC";
in {
  config = lib.mkIf cfg.enable {
    ghaf.graphics.launchers = [
      {
        name = "Terminal";
        path = "${pkgs.foot}/bin/foot";
        icon = "${pkgs.icon-pack}/utilities-terminal.svg";
      }
    ];
    environment.etc."waybar/config" = {
      text =
        # Modified from default waybar configuration file https://github.com/Alexays/Waybar/blob/master/resources/config
        ''
          {
            "height": 48, // Waybar height
            "spacing": 4, // Gaps between modules (4px)
            "modules-left": ["custom/launchpad", "custom/ghaf-settings"],
            "modules-center": ["sway/window"],
            "position": "bottom",
            "mode": "dock",
            "spacing": 4,
            "margin-top": 3,
            "margin-bottom": 5,
            "margin-left": 200,
            "margin-right": 200,
            "modules-right": ["pulseaudio", "custom/network1", "battery", "custom/admin", "clock", "tray"],
            "keyboard-state": {
                "numlock": true,
                "capslock": true,
                "format": "{name} {icon}",
                "format-icons": {
                    "locked": "",
                    "unlocked": ""
                }
            },
            "tray": {
                // "icon-size": 21,
                "spacing": 10
            },
            "clock": {
                "timezone": "${timeZone}",
                "tooltip-format": "<big>{:%d %b %Y}</big>\n<tt><small>{calendar}</small></tt>",
                // should be "{:%a %-d %b %-I:%M %#p}"
                // see github.com/Alexays/Waybar/issues/1469
                "format": "{:%a %d %b   %I:%M %p}"
            },
            "backlight": {
                // "device": "acpi_video1",
                "format": "{percent}% {icon}",
                "tooltip-format": "Brightness: {percent}%",
                "format-icons": ["", "", "", "", "", "", "", "", ""]
            },
            "battery": {
                "states": {
                    "critical": 15
                },
                "interval": 5,
                "format": "{capacity}% {icon}",
                "format-charging": "{capacity}% 󰢟",
                "format-plugged": "{capacity}% ",
                "format-alt": "{time} {icon}",
                "format-icons": ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
            },
        ''
        + lib.optionalString (wifiDevice != null) ''
          "custom/network1": {
            "format": "{}",
            "interval": 15,
            "exec": "${wifi-signal-strength}/bin/wifi-signal-strength",
            "return-type": "json",
            "on-click": "nm-launcher",
          },
        ''
        + ''
              "custom/launchpad": {
                "format": " ",
                "on-click": "${ghaf-launcher}/bin/ghaf-launcher",
                "tooltip": false
              },
              "custom/ghaf-settings": {
                "format": " ",
                // Placeholder for the actual Ghaf settings app
                "on-click": "${pkgs.libnotify}/bin/notify-send 'Ghaf Platform ${lib.strings.fileContents ../../../.version}'",
                "tooltip": false
              },
              "custom/admin": {
                "format": " ",
                "on-click": "${pkgs.nm-launcher.override {inherit (config.ghaf.users.accounts) uid;}}/bin/nm-launcher",
                "tooltip": false
              },
              "pulseaudio": {
                  // "scroll-step": 1, // %, can be a float
                  "format": "{volume}% {icon} {format_source}",
                  "format-bluetooth": "{volume}% {icon} {format_source}",
                  "format-bluetooth-muted": " {icon} {format_source}",
                  "format-muted": "󰝟 {format_source}",
                  "format-source": "{volume}% ",
                  "format-source-muted": "",
                  "format-icons": {
                      "headphone": "",
                      "default": ["", "", ""]
                  },
              },
          }'';

      # The UNIX file mode bits
      mode = "0644";
    };
    environment.etc."waybar/style.css" = {
      text =
        # Modified from default waybar style file https://github.com/Alexays/Waybar/blob/master/resources/style.css
        ''
          * {
              font-family: FontAwesome, Inter, sans-serif;
              font-size: 16px;
              border: none;
              border-radius: 5px;
          }

          window#waybar {
              background-color: rgba(32, 32, 32, 0.9);
              color: #ffffff;
              transition-property: background-color;
              transition-duration: .5s;
          }

          window#waybar.hidden {
              opacity: 0.2;
          }

          window#waybar.termite {
              background-color: #3F3F3F;
          }

          window#waybar.chromium {
              background-color: #000000;
              border: none;
          }

          button {
              box-shadow: inset 0 -3px transparent;
              border: none;
              border-radius: 0;
          }

          button:hover {
              background: inherit;
              box-shadow: inset 0 -3px #ffffff;
          }

          #workspaces button {
              padding: 0 5px;
              background-color: transparent;
              color: #ffffff;
          }

          #workspaces button:hover {
              background: rgba(0, 0, 0, 0.2);
          }

          #workspaces button.focused {
              box-shadow: inset 0 -3px #ffffff;
          }


          #clock,
          #battery,
          #backlight,
          #custom-network1,
          #custom-launchpad,
          #custom-ghaf-settings,
          #custom-admin,
          #pulseaudio,
          #tray,
          #window,
          #workspaces {
              padding: 0 20px;
          }

          .modules-left > widget:first-child > #workspaces {
              margin-left: 0;
          }

          .modules-right > widget:last-child > #workspaces {
              margin-right: 0;
          }

          #pulseaudio,
          #custom-network1,
          #backlight,
          #battery,
          #clock {
              padding-left: 10;
              padding-right: 10;
          }

          label:focus {
              background-color: #000000;
          }

          #tray > .passive {
              -gtk-icon-effect: dim;
          }

          #custom-launchpad {
              font-size: 20px;
              background-image: url("${launchpad-icon}");
              background-position: center;
              background-repeat: no-repeat;
              margin-left: 13px;
          }

          #custom-ghaf-settings {
              font-size: 20px;
              background-image: url("${ghaf-icon}");
              background-position: center;
              background-repeat: no-repeat;
              padding-left: 10;
              padding-right: 10;
          }

          #custom-admin {
              font-size: 20px;
              background-image: url("${admin-icon}");
              background-position: center;
              background-repeat: no-repeat;
              padding-left: 10;
              padding-right: 10;
          }
        '';

      # The UNIX file mode bits
      mode = "0644";
    };
  };
}
