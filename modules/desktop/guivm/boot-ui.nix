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
  # Wait for UID>=1000 session to become active with valid seat
  wait-for-session = pkgs.writeShellApplication {
    name = "wait-for-session";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
    ];
    text = ''
      echo "Waiting for user to login..."
      USER_ID=1
      while [ "$USER_ID" -lt 1000 ]; do
        tmp_id=$(loginctl list-sessions --json=short | jq -e '.[] | select(.seat != null) | .uid') || true
        [[ "$tmp_id" =~ ^[0-9]+$ ]] && USER_ID="$tmp_id" || USER_ID=1
        sleep 1
      done
      echo "User with ID=$USER_ID is now active"

      echo "Waiting for user-session to be running..."
      while [ ! -S "/run/user/$USER_ID/bus" ]; do
        sleep 1
      done
      echo "User-session is active"
    '';
  };

  # Only enable if graphics boot is enabled in globalConfig
  bootEnabled = globalConfig.graphics.boot.enable or false;
in
{
  _file = ./boot-ui.nix;

  config = lib.mkIf bootEnabled {
    # Allow systemd units to be monitored via givc
    givc.sysvm.capabilities.services = [
      "greetd.service"
      "user-login.service"
    ];

    # Wait until user logs in and ghaf-session is active.
    #
    # Type=simple (rather than oneshot) so the unit is considered started as
    # soon as wait-for-session is forked, not once it exits. That keeps this
    # off the critical path for multi-user.target (and therefore
    # systemd-analyze / Plymouth's boot-duration estimate), which would
    # otherwise count actual human login time as part of "boot finished".
    # RemainAfterExit still leaves the unit "active (exited)" once the wait
    # completes, so givc's view of it is unchanged.
    systemd.services.user-login = {
      description = "Wait for ghaf-session to be active";
      wantedBy = [ "multi-user.target" ];
      after = [ "greetd.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe wait-for-session}";
        RemainAfterExit = true;
      };
    };
  };
}
