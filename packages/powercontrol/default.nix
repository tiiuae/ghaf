# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  openssh,
  stdenv,
  writeShellScript,
}:
let
  systemctl = "/run/current-system/systemd/bin/systemctl";
  busName = "org.freedesktop.login1";

  makeSystemCtlPowerActionViaSsh =
    {
      hostAddress,
      privateSshKeyPath,
      method,
    }:
    writeShellScript "${method}-host" ''
      ${openssh}/bin/ssh \
          -i ${privateSshKeyPath} \
          -o StrictHostKeyChecking=no \
          ghaf@${hostAddress} \
          ${systemctl} ${method}'';
in
stdenv.mkDerivation {
  name = "powercontrol";

  makePowerOffCommand =
    { hostAddress, privateSshKeyPath }:
    makeSystemCtlPowerActionViaSsh {
      inherit hostAddress privateSshKeyPath;
      method = "poweroff";
    };

  makeRebootCommand =
    { hostAddress, privateSshKeyPath }:
    makeSystemCtlPowerActionViaSsh {
      inherit hostAddress privateSshKeyPath;
      method = "reboot";
    };

  makeSuspendCommand =
    { hostAddress, privateSshKeyPath }:
    makeSystemCtlPowerActionViaSsh {
      inherit hostAddress privateSshKeyPath;
      method = "suspend";
    };

  makeHibernateCommand =
    { hostAddress, privateSshKeyPath }:
    makeSystemCtlPowerActionViaSsh {
      inherit hostAddress privateSshKeyPath;
      method = "hibernate";
    };

  polkitExtraConfig = ''
    polkit.addRule(function(action, subject) {
        if ((subject.user == "ghaf") &&
           (action.id == "${busName}.power-off" ||
            action.id == "${busName}.power-off-multiple-sessions" ||
            action.id == "${busName}.reboot" ||
            action.id == "${busName}.reboot-multiple-sessions" ||
            action.id == "${busName}.suspend" ||
            action.id == "${busName}.suspend-multiple-sessions" ||
            action.id == "${busName}.hibernate" ||
            action.id == "${busName}.hibernate-multiple-sessions")
        ) {
            return polkit.Result.YES;
        }
    });
  '';

  meta = {
    description = "Scripts for host power control";
    platforms = lib.platforms.linux;
  };
}
