# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.login-manager;
  gtkgreetStyle = pkgs.writeText "gtkgreet.css" ''
    window {
      background: rgba(29, 29, 29, 1);
      color: #eee;
    }
    button {
      box-shadow: none;
      border-radius: 5px;
      border: 1px solid rgba(255, 255, 255, 0.09);
      background: rgba(255, 255, 255, 0.06);
    }
    entry {
      background-color: rgba (43, 43, 43, 1);
      border: 1px solid rgba(46, 46, 46, 1);
      color: #eee;
    }
    entry:focus {
      box-shadow: none;
      border: 1px solid rgba(223, 92, 55, 1);
    }
  '';
in
{
  options.ghaf.graphics.login-manager = {
    enable = lib.mkEnableOption "login manager using greetd";
  };

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session =
          let
            greeter-autostart = pkgs.writeShellApplication {
              name = "greeter-autostart";
              runtimeInputs = [
                pkgs.greetd.gtkgreet
                pkgs.wayland-logout
              ];
              text = ''
                gtkgreet -l -s ${gtkgreetStyle}
                wayland-logout
              '';
            };
          in
          {
            command = "${pkgs.labwc}/bin/labwc -C /etc/labwc -s ${greeter-autostart}/bin/greeter-autostart";
          };
      };
    };

    services.seatd = {
      enable = true;
      group = "video";
    };

    users.users.greeter.extraGroups = [ "video" ];

    #Allow video group to change brightness
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video $sys$devpath/brightness", RUN+="${pkgs.coreutils}/bin/chmod a+w $sys$devpath/brightness"
    '';
  };
}
