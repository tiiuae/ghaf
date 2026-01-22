# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  systemd,
  wlopm,
  libnotify,
  toybox,
  jq,
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
    toybox
    jq
  ]
  ++ (lib.optional useGivc givc-cli);

  text = ''
    help_msg() {
      cat << EOF
    Usage: $(basename "$0") <COMMAND> [OPTIONS]

    Control Ghaf power states, display power, and user sessions.

    Commands:
      reboot                  Reboot the system
      poweroff                Power off the system
      suspend                 Suspend the system after locking the session and turning off displays.
      wakeup                  Trigger wakeup procedures, such as restoring displays or USB controllers (used after suspend).
      logout                  Log out the current user using 'wayland-logout' and terminate user processes.
      turn-off-displays [DISPLAY]
                              Turn off a specific display (e.g., eDP-1), or all displays if none is provided.
      turn-on-displays [DISPLAY]
                              Turn on a specific display or all displays if none is provided.
      help, --help            Show this help message and exit.

    Examples:
      $(basename "$0") suspend
      $(basename "$0") turn-off-displays eDP-1
      $(basename "$0") turn-on-displays             # Turns on all displays

    EOF
    }

    if [ -z "$1" ]; then
        help_msg
        exit 0
    fi

    try_toggle_displays() {
      local action=$1
      local display_name=''${2:-'*'}
      local uid

      # Determine the UID of the user session to operate on
      uid=$(loginctl list-sessions --json=short | jq -e '.[] | select(.seat != null) | .uid')
      if [ -n "$uid" ]; then
        echo "Using session UID: $uid"
      else
        echo "Error: Could not determine user session UID"
        return 1
      fi

      if [ "$action" != "on" ] && [ "$action" != "off" ]; then
        echo "Error: First argument must be 'on' or 'off'"
        return 1
      fi

      local cmd="wlopm --$action '$display_name'"

      echo "Attempting to turn displays '$display_name' $action..."

      # Try without setting WAYLAND_DISPLAY
      if [ -n "$WAYLAND_DISPLAY" ]; then
        # Try without setting WAYLAND_DISPLAY
        if eval "$cmd"; then
          echo "Displays turned $action successfully on wayland socket $WAYLAND_DISPLAY"
          return 0
        fi
      fi

      echo "Searching for a valid Wayland socket..."

      for i in {0..9}; do
        export WAYLAND_DISPLAY="/run/user/$uid/wayland-$i"
        echo "Trying wayland socket $WAYLAND_DISPLAY to turn displays $action..."
        if [ -e "$WAYLAND_DISPLAY" ] && eval "$cmd"; then
          echo "Displays turned $action successfully on wayland socket $WAYLAND_DISPLAY"
          return 0
        fi
      done

      echo "Failed to turn displays $action: no valid wayland socket found"
      return 1
    }

    wakeup() {
      echo "Waking up system..."
      try_toggle_displays on
    }

    case "$1" in
      reboot|poweroff)
        systemctl "$1"
        ;;
      suspend)
      ${
        if ghafConfig.services.power-manager.allowSuspend then
          ''
            systemctl suspend
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
        loginctl kill-user "$USER" -s SIGTERM # Allow services to clean up
        ;;
      wakeup)
        # Actions to perform on wakeup
        wakeup
        ;;
      turn-off-displays)
        try_toggle_displays off "$2"
        ;;
      turn-on-displays)
        try_toggle_displays on "$2"
        ;;
      help|--help)
        help_msg
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
