# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  systemd,
  wlopm,
  libnotify,
  wayland-logout,
  givc-cli ? null,
  ghafConfig ? { },
  ghaf-artwork ? null,
}:
let
  useGivc = ghafConfig.givc.enable;
in
writeShellApplication {
  name = "ghaf-powercontrol";

  bashOptions = [ ];

  runtimeInputs = [
    systemd
    wlopm
    wayland-logout
    libnotify
  ] ++ (lib.optional useGivc givc-cli);

  text = ''
    help_msg() {
        cat << EOF
    Usage: $(basename "$0") [OPTION]

    Control Ghaf power states and user sessions.

    Options:
      reboot        Reboot the system using 'givc-cli' if enabled, otherwise 'systemctl'.
      poweroff      Power off the system using 'givc-cli' if enabled, otherwise 'systemctl'.
      suspend       Lock session, turn off display, suspend, and restore display on wake.
      logout        Log out using 'wayland-logout' and force-kill user session processes.
      help, --help  Show this help message and exit.
    EOF
    }

    if [ -z "$1" ]; then
        help_msg
        exit 0
    fi

    try_toggle_displays() {
      local cmd
      local uid=${toString ghafConfig.users.loginUser.uid}

      # Determine the wlopm command
      if [ "$1" = true ]; then
        cmd="wlopm --on '*'"
      else
        cmd="wlopm --off '*'"
      fi

      # Try wlopm without setting WAYLAND_DISPLAY first
      if eval "$cmd"; then
        echo "Displays turned on successfully"
        return 0
      fi

      # Try each wayland-N socket
      echo "Trying to find a valid wayland socket..."
      for i in {0..9}; do
        export WAYLAND_DISPLAY="/run/user/$uid/wayland-$i"
        echo "Trying WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        if [ -e "$WAYLAND_DISPLAY" ]; then
          if eval "$cmd"; then
            echo "Displays toggled successfully with WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
            return 0
          fi
        fi
      done

      echo "Could not find a valid wayland socket"
      echo "Displays could not be toggled"
      return 1
    }

    case "$1" in
      reboot|poweroff)
        ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} "$1"
        ;;
      suspend)
      ${
        if ghafConfig.profiles.graphics.allowSuspend then
          ''
            # Lock sessions
            echo "Locking session..."
            loginctl lock-session

            echo "Turning off displays..."
            try_toggle_displays false || true

            # Send suspend command to host, ensure screen is on in case of failure
            ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} suspend \
              || try_toggle_displays true || true

            # Switch on display on wakeup
            echo "Wake up detected, turning on displays..."
            try_toggle_displays true || true
          ''
        else
          ''
            MSG="Suspend functionality is currently not enabled on this system."
            echo "$MSG"
            notify-send -i ${ghaf-artwork}/icons/suspend.svg 'Ghaf Power Control' "$MSG"
            exit 1
          ''
      }
      ;;
      logout)
        wayland-logout
        loginctl terminate-user "$USER"
        sleep 2
        loginctl kill-user "$USER" -s SIGTERM
        sleep 2
        loginctl kill-user "$USER" -s SIGKILL
        ;;
      help|--help)
          help_msg
          exit 0
          ;;
      *)
          help_msg
          exit 1
          ;;
    esac
  '';

  meta = {
    description = "Wrapper script to control Ghaf power states using systemctl or GIVC.";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
