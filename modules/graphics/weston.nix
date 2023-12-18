# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
  mkLauncher = {
    path,
    icon,
  }: ''
    [launcher]
    path=${path}
    icon=${icon}

  '';

  #
  # Generate launchers to be used in weston.ini
  # Type: mkLaunchers :: [{path, icon}] -> string

  mkLaunchers = lib.concatMapStrings mkLauncher;

  defaultLauncher = [
    # Keep weston-terminal launcher always enabled explicitly since if someone adds
    # a launcher on the panel, the launcher will replace weston-terminal launcher.
    {
      path = "${pkgs.weston}/bin/weston-terminal";
      icon = "${pkgs.weston}/share/weston/icon_terminal.png";
    }
  ];
in {
  imports = [
    ./window-manager.nix
  ];

  options.ghaf.graphics.weston = {
    enable = lib.mkEnableOption "weston";

    launchers = with lib;
      mkOption {
        description = "Weston application launchers to show in launch bar";
        default = [];
        type = with types;
          listOf
          (submodule {
            options.path = mkOption {
              description = "Path to the executable to be launched";
              type = path;
            };
            options.icon = mkOption {
              description = "Path of the icon";
              type = path;
            };
          });
      };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.window-manager-common.enable = true;
    ghaf.graphics.weston.launchers = defaultLauncher;

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
        ListenStream = "%t/wayland-1";
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

    environment.etc."xdg/weston/weston.ini" = {
      text =
        ''
          # Disable screen locking
          [core]
          idle-time=0

          [shell]
          locking=false
          background-image=${../../assets/wallpaper.png}
          background-type=scale-crop
          num-workspaces=2

          # Set the keyboard layout for weston to US by default
          [keyboard]
          keymap_layout=us,fi

          # Enable Hack font for weston-terminal
          [terminal]
          font=Hack
          font-size=16

        ''
        + mkLaunchers cfg.launchers;

      # The UNIX file mode bits
      mode = "0644";
    };
  };
}
