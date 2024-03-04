# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
  waylandSocket = "wayland-1";
in {
  options.ghaf.graphics.weston = {
    enable = lib.mkEnableOption "weston";
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.window-manager-common.enable = true;

    environment.systemPackages = with pkgs; [
      weston
    ];

    # Next 2 services/targets are taken from official weston documentation:
    # https://wayland.pages.freedesktop.org/weston/toc/running-weston.html

    # Weston socket
    systemd.user.sockets."weston" = {
      unitConfig = {
        Description = "Weston, a Wayland compositor";
        Documentation = "man:weston(1) man:weston.ini(5)";
      };
      socketConfig = {
        ListenStream = "%t/${waylandSocket}";
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
        Type = "notify";
        #TimeoutStartSec = "60";
        #WatchdogSec = "20";
        # Defaults to journal
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${pkgs.weston}/bin/weston --modules=systemd-notify.so";
        #GPU pt needs some time to start - weston fails to restart 3 times in avg.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        # Set WAYLAND_DISPLAY variable to make it available to waypipe and other systemd services
        ExecStartPost = "${pkgs.systemd}/bin/systemctl --user set-environment WAYLAND_DISPLAY=${waylandSocket}";
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
  };
}
