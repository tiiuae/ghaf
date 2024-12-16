# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ghafConfig,
  systemd,
  wlopm,
  givc-cli,
  ...
}:
let
  inherit (builtins) replaceStrings;
  inherit (lib) optionalString;
  cliArgs = replaceStrings [ "\n" ] [ " " ] ''
    --name ${ghafConfig.givc.adminConfig.name}
    --addr ${ghafConfig.givc.adminConfig.addr}
    --port ${ghafConfig.givc.adminConfig.port}
    ${optionalString ghafConfig.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
    ${optionalString ghafConfig.givc.enableTls "--cert /run/givc/gui-vm-cert.pem"}
    ${optionalString ghafConfig.givc.enableTls "--key /run/givc/gui-vm-key.pem"}
    ${optionalString (!ghafConfig.givc.enableTls) "--notls"}
  '';
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
  ] ++ (lib.optional useGivc givc-cli);
  text = ''
    case "$1" in
      reboot|poweroff)
        ${if useGivc then "givc-cli ${cliArgs}" else "systemctl"} "$1"
        ;;
      suspend)
        # Lock sessions
        loginctl lock-session

        # Switch off display before suspension
        ${waylandDisplayCmd "off"}

        # Send suspend command to host, ensure screen is on in case of failure
        ${if useGivc then "givc-cli ${cliArgs}" else "systemctl"} suspend \
          || ${waylandDisplayCmd "on"}

        # Switch on display on wakeup
        ${waylandDisplayCmd "on"}
        ;;
      *)
        echo "Unknown option. Supported: reboot, poweroff, suspend."
        exit 1
        ;;
    esac
  '';

  meta = {
    description = "Wrapper script to control Ghaf power states using systemctl or GIVC.";
    platforms = lib.platforms.linux;
  };
}
