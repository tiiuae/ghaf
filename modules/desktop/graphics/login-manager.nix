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

  gtkgreetStyle = pkgs.callPackage ./styles/login-style.nix { };
in
{
  options.ghaf.graphics.login-manager = {
    enable = lib.mkEnableOption "login manager using greetd";
  };

  config = lib.mkIf cfg.enable {
    services = {
      greetd = {
        enable = true;
        settings = {
          default_session =
            let
              greeter-autostart = pkgs.writeShellApplication {
                name = "greeter-autostart";
                runtimeInputs = [
                  pkgs.greetd.gtkgreet
                  pkgs.wayland-logout
                  pkgs.brightnessctl
                ];
                text = ''
                  # By default set system brightness to 100% which can be configured later
                  brightnessctl set 100%
                  gtkgreet -l -s ${gtkgreetStyle}
                  wayland-logout
                '';
              };
            in
            {
              command = "${pkgs.labwc}/bin/labwc -C /etc/labwc -s ${greeter-autostart}/bin/greeter-autostart >/tmp/greeter.labwc.log 2>&1";
            };
        };
      };

      seatd = {
        enable = true;
        group = "video";
      };

      #Allow video group to change brightness
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video $sys$devpath/brightness", RUN+="${pkgs.coreutils}/bin/chmod a+w $sys$devpath/brightness"
      '';
    };

    systemd.services.greetd.serviceConfig = {
      RestartSec = "5";
    };

    users.users.greeter.extraGroups = [ "video" ];
  };
}
