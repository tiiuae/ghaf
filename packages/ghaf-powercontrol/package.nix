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
  # Handle Wayland display power state
  waylandDisplayCmd = command: ''
    WAYLAND_DISPLAY=/run/user/${builtins.toString ghafConfig.users.loginUser.uid}/wayland-0 \
    wlopm --${command} '*'
  '';
in
writeShellApplication {
  name = "ghaf-powercontrol";

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

    case "$1" in
      reboot|poweroff)
        ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} "$1"
        ;;
      suspend)
      ${
        if ghafConfig.profiles.graphics.allowSuspend then
          ''
            # Lock sessions
            loginctl lock-session

            # Switch off display before suspension
            ${waylandDisplayCmd "off"}

            # Send suspend command to host, ensure screen is on in case of failure
            ${if useGivc then "givc-cli ${ghafConfig.givc.cliArgs}" else "systemctl"} suspend \
              || ${waylandDisplayCmd "on"}

            # Switch on display on wakeup
            ${waylandDisplayCmd "on"}
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
