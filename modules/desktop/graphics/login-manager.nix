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

  inherit (lib)
    mkIf
    mkEnableOption
    ;

  useCosmic = config.ghaf.profiles.graphics.compositor == "cosmic";

  useLabwc = config.ghaf.profiles.graphics.compositor == "labwc";

  greeterUser = if useCosmic then "cosmic-greeter" else "greeter";

  gtkgreetStyle = pkgs.callPackage ./styles/login-style.nix { };
in
{
  options.ghaf.graphics.login-manager = {
    enable = mkEnableOption "Ghaf login manager config using greetd";
  };

  config = mkIf cfg.enable {
    # Ensure internal display is at full brightness for labwc
    services = mkIf useLabwc {
      greetd = {
        enable = true;
        settings = {
          default_session =
            let
              greeter-autostart = pkgs.writeShellApplication {
                name = "greeter-autostart";
                runtimeInputs = [
                  pkgs.brightnessctl
                  pkgs.greetd.gtkgreet
                  pkgs.wayland-logout
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
              command = lib.mkForce "${lib.getExe pkgs.labwc} -C /etc/labwc -s ${lib.getExe greeter-autostart} >/tmp/greeter.labwc.log 2>&1";
            };
        };
      };

      seatd = {
        enable = true;
        group = "video";
      };

      #Allow video group to change brightness
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="backlight", RUN+="${lib.getExe' pkgs.coreutils "chgrp"} video $sys$devpath/brightness", RUN+="${lib.getExe' pkgs.coreutils "chmod"} a+w $sys$devpath/brightness"
      '';
    };

    systemd.services.greetd.serviceConfig = {
      RestartSec = "5";
    };

    users.users.${greeterUser}.extraGroups = [ "video" ];

    # Needed for the greeter to query systemd-homed users correctly
    systemd.services.cosmic-greeter-daemon.environment.LD_LIBRARY_PATH = mkIf useCosmic "${
      pkgs.lib.makeLibraryPath
      [
        pkgs.systemd
      ]
    }";

    security.pam.services = {
      cosmic-greeter.rules.auth = mkIf useCosmic {
        systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint on lockscreen
        fprintd.args = [ "maxtries=3" ];
      };
      gtklock.rules.auth = mkIf useLabwc {
        systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint on lockscreen
        fprintd.args = [ "maxtries=3" ];
      };
      greetd = {
        fprintAuth = false; # User needs to enter password to decrypt home on login
        rules = {
          account.group_video = {
            enable = true;
            control = "requisite";
            modulePath = "${pkgs.linux-pam}/lib/security/pam_succeed_if.so";
            order = 10000;
            args = [
              "user"
              "ingroup"
              "video"
            ];
          };
        };
      };
    };
  };
}
