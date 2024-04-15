# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  networkDevice = config.ghaf.hardware.definition.network.pciDevices;

  ghaf-icon = pkgs.runCommand "ghaf-icon-24x24" {} ''
    mkdir -p $out/share/icons/hicolor/24x24/apps
    ${pkgs.buildPackages.imagemagick}/bin/convert \
      ${../../../assets/ghaf-logo.png} \
      -resize 24x24 \
      $out/share/icons/hicolor/24x24/apps/ghaf-icon-24x24.png
  '';

  wifiDevice = lib.lists.findFirst (d: d.name != null) null networkDevice;
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
        icon = "${pkgs.foot}/share/icons/hicolor/48x48/apps/foot.png";
      }
    ];
    environment.etc."waybar/config" = {
      text =
        # Modified from default waybar configuration file https://github.com/Alexays/Waybar/blob/master/resources/config
        ''
          {
            "height": 30, // Waybar height (to be removed for auto height)
            "spacing": 4, // Gaps between modules (4px)
            "modules-left": ["custom/launcher"],
            "modules-center": ["sway/window"],
            "modules-right": ["pulseaudio", "custom/network1", "backlight", "battery", "clock", "tray"],
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
              "custom/launcher": {
                "format": " ",
                "on-click": "${ghaf-launcher}/bin/ghaf-launcher",
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
              font-family: FontAwesome, Inter, Roboto, sans-serif;
              font-size: 14px;
          }

          window#waybar {
              background-color: rgba(43, 48, 59, 0.5);
              border-bottom: 3px solid rgba(100, 114, 125, 0.5);
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
              background-color: #64727D;
              box-shadow: inset 0 -3px #ffffff;
          }

          #workspaces button.urgent {
              background-color: #eb4d4b;
          }

          #clock,
          #battery,
          #backlight,
          #custom-network1,
          #custom-launcher,
          #pulseaudio,
          #tray,
          #window,
          #workspaces {
              margin: 0 4px;
          }

          .modules-left > widget:first-child > #workspaces {
              margin-left: 0;
          }

          .modules-right > widget:last-child > #workspaces {
              margin-right: 0;
          }

          #clock {
              background-color: #64727D;
              padding-left: 10;
              padding-right: 10;
          }

          #battery {
              background-color: #ffffff;
              color: #000000;
              padding-left: 10;
              padding-right: 10;
          }

          #battery.charging, #battery.plugged {
              color: #ffffff;
              background-color: #26A65B;
          }

          @keyframes blink {
              to {
                  background-color: #ffffff;
                  color: #000000;
              }
          }

          #battery.critical:not(.charging) {
              background-color: #f53c3c;
              color: #ffffff;
              animation-name: blink;
              animation-duration: 0.5s;
              animation-timing-function: linear;
              animation-iteration-count: infinite;
              animation-direction: alternate;
          }

          label:focus {
              background-color: #000000;
          }

          #backlight {
              background-color: #90b1b1;
              padding-left: 10;
              padding-right: 10;
          }

          #custom-network1 {
              background-color: #2980b9;
              min-width: 16px;
              padding-left: 10;
              padding-right: 10;
          }

          #custom-network1.disconnected {
              background-color: #f53c3c;
          }

          #pulseaudio {
              background-color: #f1c40f;
              color: #000000;
              padding-left: 10;
              padding-right: 10;
          }

          #pulseaudio.muted {
              background-color: #90b1b1;
              color: #2a5c45;
          }

          #tray {
              background-color: #2980b9;
          }

          #tray > .passive {
              -gtk-icon-effect: dim;
          }

          #tray > .needs-attention {
              -gtk-icon-effect: highlight;
              background-color: #eb4d4b;
          }

          #language {
              background: #00b093;
              color: #740864;
              padding: 0 5px;
              margin: 0 5px;
              min-width: 16px;
          }

          #keyboard-state {
              background: #97e1ad;
              color: #000000;
              padding: 0 0px;
              margin: 0 5px;
              min-width: 16px;
          }

          #keyboard-state > label {
              padding: 0 5px;
          }

          #keyboard-state > label.locked {
              background: rgba(0, 0, 0, 0.2);
          }
          #custom-launcher {
              font-size: 20px; background-image: url("${ghaf-icon}/share/icons/hicolor/24x24/apps/ghaf-icon-24x24.png");
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
