# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  brightnessctl,
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
    brightnessctl
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
      local action=$1
      local uid

      # Determine the UID of the user session to operate on
      uid=$(loginctl list-sessions --json=short | jq -e '.[] | select(.class == "greeter") | .uid')
      if [ -n "$uid" ]; then
        echo "Using greeter session UID: $uid"
      else
        uid=${toString ghafConfig.users.loginUser.uid}
        echo "Using login user session UID: $uid"
      fi

      if [ "$action" != "on" ] && [ "$action" != "off" ]; then
        echo "Error: First argument must be 'on' or 'off'"
        return 1
      fi

      # We mimic the behavior of wlopm to turn off displays
      # by using brightnessctl to set the brightness to 0% or 100%
      # TODO: Investigate why cosmic-comp crashes when using wlopm
      # local cmd="wlopm --$action '*'"
      local brightness
      if [[ $action == "on" ]]; then
        brightness="100%"
      else
        brightness="0%"
      fi
      local cmd="brightnessctl set $brightness"

      echo "Attempting to turn displays $action..."

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

    reset_xhci_controllers() {
      echo "Resetting USB controllers..."
      # Find all USB controller PCI addresses
      local controllers
      controllers=$(lspci -Dnmm | grep -i '0c03' | cut -f1 -d' ')

      if [ -z "$controllers" ]; then
        echo "No USB controllers found"
        return 0
      fi

      echo "Found USB controllers: $controllers" | xargs

      for dev in $controllers; do
        if [ -L "/sys/bus/pci/devices/$dev/driver" ]; then
          echo "Unbinding $dev"
          if ! echo -n "$dev" > /sys/bus/pci/drivers/xhci_hcd/unbind; then
            echo "ERROR: Failed to unbind $dev"
            return 1
          fi
        else
          echo "Device already unbinded"
        fi
        echo "Rebinding $dev"
        if ! echo -n "$dev" > /sys/bus/pci/drivers/xhci_hcd/bind; then
          echo "ERROR: Failed to bind $dev"
          return 1
        fi
      done
      echo "USB controllers reset successfully"
      sleep 1
    }

    case "$1" in
      reboot|poweroff)
        ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} "$1"
        ;;
      suspend)
      ${
        if ghafConfig.profiles.graphics.allowSuspend then
          ''
            echo "Turning off displays..."
            try_toggle_displays off

            echo "Locking session..."
            loginctl lock-session

            # givc-cli seems to always return a non-zero exit code,
            # so we must have a separate fail-safe to turn on displays
            ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} suspend || true
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
        ${lib.optionalString useGivc "reset_xhci_controllers"} # Only needed if waking up a VM
        try_toggle_displays on
        ;;
      turn-off-displays)
        try_toggle_displays off
        ;;
      turn-on-displays)
        try_toggle_displays on
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
