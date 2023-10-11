# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.window-manager-common;
in {
  options.ghaf.graphics.window-manager-common = with lib; {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Common parts for every wlroots-based window manager/compositor.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.opengl = {
      enable = true;
      driSupport = true;
    };

    environment.noXlibs = false;

    environment.systemPackages = with pkgs; [
      # Seatd is needed to manage log-in process for wayland sessions
      seatd
    ];

    # Next services/targets are taken from official weston documentation:
    # https://wayland.pages.freedesktop.org/weston/toc/running-weston.html

    systemd.user.targets."ghaf-session" = {
      description = "Ghaf graphical session";
      bindsTo = ["ghaf-session.target"];
      before = ["ghaf-session.target"];
    };

    systemd.services."ghaf-session" = {
      description = "Ghaf graphical session";

      # Make sure we are started after logins are permitted.
      after = ["systemd-user-sessions.service"];

      # if you want you can make it part of the graphical session
      #Before=graphical.target

      # not necessary but just in case
      #ConditionPathExists=/dev/tty7

      serviceConfig = {
        Type = "simple";
        Environment = "XDG_SESSION_TYPE=wayland";
        ExecStart = "${pkgs.systemd}/bin/systemctl --wait --user start ghaf-session.target";

        # The user to run the session as. Pick one!
        User = config.ghaf.users.accounts.user;
        Group = config.ghaf.users.accounts.user;

        # Set up a full user session for the user, required by desktop environment.
        PAMName = "${pkgs.shadow}/bin/login";

        # A virtual terminal is needed.
        TTYPath = "/dev/tty7";
        TTYReset = "yes";
        TTYVHangup = "yes";
        TTYVTDisallocate = "yes";

        # Try to grab tty .
        StandardInput = "tty-force";

        # Defaults to journal, in case it doesn't adjust it accordingly
        #StandardOutput=journal
        StandardError = "journal";

        # Log this user with utmp, letting it show up with commands 'w' and 'who'.
        UtmpIdentifier = "tty7";
        UtmpMode = "user";
      };
      wantedBy = ["multi-user.target"];
    };

    # systemd service for seatd
    systemd.services."seatd" = {
      description = "Seat management daemon";
      documentation = ["man:seatd(1)"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.seatd}/bin/seatd -g video";
        Restart = "always";
        RestartSec = "1";
      };
      wantedBy = ["multi-user.target"];
    };
  };
}
