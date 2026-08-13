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
  # Wait for a real non-root user session, not the display-manager greeter.
  wait-for-session = pkgs.writeShellApplication {
    name = "wait-for-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      echo "Waiting for user to login..."
      USER_ID=0
      while [ "$USER_ID" -eq 0 ]; do
        active_session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)"
        tmp_id="$(loginctl show-session "$active_session" -p User --value 2>/dev/null || true)"
        seat="$(loginctl show-session "$active_session" -p Seat --value 2>/dev/null || true)"
        session_class="$(loginctl show-session "$active_session" -p Class --value 2>/dev/null || true)"

        if [[ "$tmp_id" =~ ^[0-9]+$ ]] && [ "$tmp_id" -gt 0 ] && [ -n "$seat" ] && [ "$session_class" = "user" ]; then
          USER_ID="$tmp_id"
        else
          USER_ID=0
        fi
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

    # Wait until user logs in and ghaf-session is active
    systemd.services.user-login = {
      description = "Wait for ghaf-session to be active";
      wantedBy = [ "multi-user.target" ];
      after = [ "greetd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe wait-for-session}";
        RemainAfterExit = true;
      };
    };
  };
}
