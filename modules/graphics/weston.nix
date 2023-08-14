# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
in {
  options.ghaf.graphics.weston = {
    enable = lib.mkEnableOption "weston";
  };

  config = lib.mkIf cfg.enable {
    hardware.opengl = {
      enable = true;
      driSupport = true;
    };

    environment.noXlibs = false;
    environment.systemPackages = with pkgs; [
      weston
      # Seatd is needed to manage log-in process for weston
      seatd
    ];

    # Next 4 services/targets are taken from official weston documentation:
    # https://wayland.pages.freedesktop.org/weston/toc/running-weston.html
    #
    # To run weston, after log-in to VT or SSH run:
    # systemctl --user start weston.service
    #
    # I am pretty sure it is possible to have it running automatically, I just
    # haven't found the way yet.

    # Weston socket
    systemd.user.sockets."weston" = {
      unitConfig = {
        Description = "Weston, a Wayland compositor";
        Documentation = "man:weston(1) man:weston.ini(5)";
      };
      socketConfig = {
        ListenStream = "%t/wayland-0";
      };
      wantedBy = ["weston.service"];
    };

    # Weston service
    systemd.user.services."weston" = {
      enable = true;
      description = "Weston, a Wayland compositor, as a user service TEST";
      documentation = ["man:weston(1) man:weston.ini(5)" "https://wayland.freedesktop.org/"];
      requires = ["weston.socket"];
      after = ["weston.socket" "ghaf-session.service"];
      serviceConfig = {
        # Previously there was "notify" type, but for some reason
        # systemd kills weston.service because of timeout (even if it is disabled).
        # "simple" works pretty well, so let's leave it.
        Type = "simple";
        #TimeoutStartSec = "60";
        #WatchdogSec = "20";
        # Defaults to journal
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${pkgs.weston}/bin/weston";
        #GPU pt needs some time to start - weston fails to restart 3 times in avg.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        Restart = "on-failure";
        RestartSec = "1";
        # Ivan N: I do not know if this is bug or feature of NixOS, but
        # when I add weston.ini file to environment.etc, the file ends up in
        # /etc/xdg directory on the filesystem, while NixOS uses
        # /run/current-system/sw/etc/xdg directory and goes into same directory
        # searching for weston.ini even if /etc/xdg is already in XDG_CONFIG_DIRS
        # The solution is to add /etc/xdg one more time for weston service.
        # It does not affect on system-wide XDG_CONFIG_DIRS variable.
        #
        # Ivan N: adding openssh into the PATH since it is needed for waypipe to work
        Environment = "XDG_CONFIG_DIRS=$XDG_CONFIG_DIRS:/etc/xdg PATH=${pkgs.openssh}/bin:$PATH";
      };
      wantedBy = ["default.target"];
    };

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

        # Set up a full user session for the user, required by Weston.
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
