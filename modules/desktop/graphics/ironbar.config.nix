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
  wifiDevice = lib.lists.findFirst (d: d.name != null) null pciDevices;
  wifi-signal-strength = pkgs.callPackage ../../../packages/wifi-signal-strength {wifiDevice = wifiDevice.name;};
  ironbarConfig = builtins.toJSON {
    name = "main";
    position = "bottom";
    anchor_to_edges = true;
    height = 48;
    margin = {
      left = 200;
      right = 200;
      top = 3;
      bottom = 5;
    };
    start = [
      {
        name = "launchers-left";
        type = "custom";
        bar = [
          {
            type = "image";
            src = "file://${../../../assets/icons/svg/launchpad.svg}";
            size = 38;
            name = "launchpad";
            on_click_left = "${pkgs.procps}/bin/pkill -USR1 nwg-drawer";
          }
          {
            type = "image";
            src = "file://${../../../assets/icons/svg/ghaf-white.svg}";
            size = 24;
            name = "ghaf-settings";
            on_click_left = "${pkgs.libnotify}/bin/notify-send 'Ghaf Platform ${lib.strings.fileContents ../../../.version}'";
          }
        ];
      }
      {
        type = "launcher";
        icon_size = 20;
        show_icons = false;
        show_names = true;
        truncate = {
          mode = "end";
          max_length = 25;
        };
      }
    ];
    end =
      lib.optionals (wifiDevice != null) [
        {
          name = "wifi-right";
          type = "custom";
          bar = [
            {
              on_click = "popup:toggle";
              label = "{{3000:${wifi-signal-strength}/bin/wifi-signal-strength | ${pkgs.jq}/bin/jq -r .signal}}";
              name = "wifi-btn";
              type = "button";
            }
          ];
          popup = [
            {
              orientation = "vertical";
              type = "box";
              class = "wifi-popup";
              widgets = [
                {
                  name = "ssid";
                  label = "{{3000:${wifi-signal-strength}/bin/wifi-signal-strength | ${pkgs.jq}/bin/jq -r .ssid}}";
                  type = "label";
                }
                {
                  name = "ip";
                  label = "{{3000:${wifi-signal-strength}/bin/wifi-signal-strength | ${pkgs.jq}/bin/jq -r .ip}}";
                  type = "label";
                }
              ];
            }
          ];
        }
      ]
      ++ [
        {
          type = "volume";
        }
        {
          name = "battery";
          type = "upower";
        }
        {
          name = "launchers-right";
          type = "custom";
          bar = [
            {
              type = "image";
              src = "file://${../../../assets/icons/svg/admin-cog.svg}";
              size = 24;
              name = "admin";
              on_click_left = "${pkgs.nm-launcher}/bin/nm-launcher";
            }
          ];
        }
        {
          type = "clock";
          format = "%a %e %b %l:%M %p";
        }
      ];
  };
  ironbarStyle = ''
    * {
      font-family: Inter, sans-serif;
      font-size: 16px;
      border: none;
      border-radius: 7px;
      box-shadow: none;
      text-shadow: none;
    }
    .background {
      background-color: rgba(32, 32, 32, 0.9);
    }
    scale trough {
      min-width: 1px;
      min-height: 2px;
    }

    box, menubar, button, image {
      background: none;
      border: none;
      box-shadow: none;
    }
    button, label {
      color: #fff;
    }

    .popup {
      padding: 0.75em;
    }

    /* Launcher */
    .launcher .item {
      background-color: rgba(32, 32, 32, 0.9);
      margin: 5px;
    }
    .launcher {
      margin-left: 10px;
    }
    #launchpad, #ghaf-settings, #admin, #wifi {
      margin-left: 15px;
    }
    .popup-launcher .popup-item:hover {
      background-color: rgba(32, 32, 32, 0.9);
    }
    /* To preserve colour & text position when item loses focus */
    .launcher .item {
      border-radius: 3px;
      border-bottom: solid 3px rgba(32, 32, 32, 0.9);
    }
    .launcher .item.focused {
      border-bottom: solid 3px #5ac379;
    }
    .launcher .item.urgent {
      border-bottom: solid 3px #f15025;
    }
  '';
in {
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "ironbar/config.json".text = ironbarConfig;
      "ironbar/style.css".text = ironbarStyle;
    };
  };
}
