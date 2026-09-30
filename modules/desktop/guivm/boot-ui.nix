# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Boot UI Feature Module
#
# This module configures boot-related services for the GUI VM including:
# - GIVC service monitoring for greetd and user-login
# - User login detection service
#
# This module is enabled automatically when ghaf.graphics.boot.enable is true.
#
{
  lib,
  pkgs,
  config,
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
        session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)"

        if [ -n "$session" ]; then
          uid=""
          seat=""
          class=""
          while IFS='=' read -r key value; do
            case "$key" in
              User) uid="$value" ;;
              Seat) seat="$value" ;;
              Class) class="$value" ;;
            esac
          done < <(loginctl show-session "$session" -p User -p Seat -p Class 2>/dev/null || true)

          if [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -gt 0 ] && [ -n "$seat" ] && [ "$class" = "user" ]; then
            USER_ID="$uid"
            break
          fi
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

  bootEnabled = config.ghaf.graphics.boot.enable;
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
    # Type 'simple' marks the unit started as soon as wait-for-session is
    # forked, so multi-user.target isn't blocked on human login time.
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
