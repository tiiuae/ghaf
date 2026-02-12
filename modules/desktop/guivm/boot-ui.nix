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
      state="inactive"
      while [[ "$state" != "active" ]]; do
        state=$(systemctl --user is-active session.slice --machine="$USER_ID"@.host) || true
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
