# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Boot UI Feature Module
#
# This module configures boot-related services for the GUI VM including:
# - GIVC service monitoring for greetd and user-login
# - User login detection service
#
# This module is auto-included when ghaf.graphics.boot.enable is true.
#
{
  lib,
  pkgs,
  globalConfig,
  ...
}:
let
  # Wait for ghaf-session to become active
  wait-for-session = pkgs.writeShellApplication {
    name = "wait-for-session";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      # Loop until ghaf-session.target is active
      while ! systemctl --user is-active ghaf-session.target > /dev/null 2>&1; do
        sleep 1
      done
    '';
  };

  # Only enable if graphics boot is enabled in globalConfig
  bootEnabled = globalConfig.graphics.boot.enable or false;
in
{
  _file = ./boot-ui.nix;

  config = lib.mkIf bootEnabled {
    # Allow systemd units to be monitored via givc
    givc.sysvm.services = [
      "greetd.service"
      "user-login.service"
    ];

    # Wait until user logs in and ghaf-session is active
    systemd.services.user-login = {
      description = "Wait for ghaf-session to be active";
      wantedBy = [ "multi-user.target" ];
      after = [ "greetd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${lib.getExe wait-for-session}";
        ExecStart = "/bin/sh -c exit"; # no-op
        RemainAfterExit = true;
      };
    };
  };
}
