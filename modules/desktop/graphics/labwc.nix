# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.labwc;
  screen_lock_cmd =
    if config.ghaf.graphics.labwc.lock.enable
    then ''
      # Lock screen after 5 minutes
      ${pkgs.swayidle}/bin/swayidle -w timeout 300 \
      '${pkgs.swaylock-effects}/bin/swaylock -f -c 000000 \
      --clock --indicator --indicator-radius 150 --inside-ver-color 5ac379' &
    ''
    else "";
  launchers = pkgs.callPackage ./launchers.nix {inherit config;};
in {
  options.ghaf.graphics.labwc = {
    enable = lib.mkEnableOption "labwc";
  };

  options.ghaf.graphics.labwc.lock.enable = lib.mkOption {
    description = "Labwc screen locking";
    type = lib.types.bool;
    default = false;
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.window-manager-common.enable = true;

    environment.systemPackages = with pkgs;
      [labwc launchers]
      # Below sway packages needed for screen locking
      ++ lib.optionals config.ghaf.graphics.labwc.lock.enable [swaylock-effects swayidle];

    # It will create /etc/pam.d/swaylock file for authentication
    security.pam.services = lib.mkIf config.ghaf.graphics.labwc.lock.enable {swaylock = {};};

    # Next 2 services/targets are taken from official weston documentation
    # and adjusted for labwc
    # https://wayland.pages.freedesktop.org/weston/toc/running-weston.html
    systemd.user.services."labwc" = let
      autostart =
        pkgs.concatScript "labwc-autostart"
        [
          "${pkgs.labwc}/share/doc/labwc/autostart"
          (pkgs.writeText "autostart-extra" ''
            # Import WAYLAND_DISPLAY variable to make it available to waypipe and other systemd services
            ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY 2>&1 &
            ${screen_lock_cmd}
          '')
        ];
    in {
      enable = true;
      description = "labwc, a Wayland compositor, as a user service TEST";
      documentation = ["man:labwc(1)"];
      after = ["ghaf-session.service"];
      serviceConfig = {
        # Previously there was "notify" type, but for some reason
        # systemd kills labwc.service because of timeout (even if it is disabled).
        # "simple" works pretty well, so let's leave it.
        Type = "simple";
        #TimeoutStartSec = "60";
        #WatchdogSec = "20";
        # Defaults to journal
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${pkgs.labwc}/bin/labwc -C ${pkgs.labwc}/share/doc/labwc -s ${autostart}";
        #GPU pt needs some time to start - labwc fails to restart 3 times in avg.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        Restart = "on-failure";
        RestartSec = "1";

        # Ivan N: adding openssh into the PATH since it is needed for waypipe to work
        Environment = "PATH=${pkgs.openssh}/bin:$PATH";
      };
      environment = {
        WLR_RENDERER = "pixman";
        # See: https://github.com/labwc/labwc/blob/0.6.5/docs/environment
        XKB_DEFAULT_LAYOUT = "us,fi";
      };
      wantedBy = ["default.target"];
    };
  };
}
