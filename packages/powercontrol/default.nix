# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  openssh,
  stdenv,
  writeShellScript,
  user,
}: let
  systemctl = "/run/current-system/systemd/bin/systemctl";
  busName = "org.freedesktop.login1";

  makeSystemCtlPowerActionViaSsh = {
    hostAddress,
    sshKeyPath,
    method,
  }:
    writeShellScript
    "${method}-host"
    ''      ${openssh}/bin/ssh \
          -i ${sshKeyPath} \
          -o StrictHostKeyChecking=no \
            ${user}@${hostAddress} \
          ${systemctl} ${method}'';
in
  stdenv.mkDerivation {
    name = "powercontrol";

    makePowerOffCommand = {
      hostAddress,
      sshKeyPath,
    }:
      makeSystemCtlPowerActionViaSsh {
        inherit hostAddress sshKeyPath;
        method = "poweroff";
      };

    makeRebootCommand = {
      hostAddress,
      sshKeyPath,
    }:
      makeSystemCtlPowerActionViaSsh {
        inherit hostAddress sshKeyPath;
        method = "reboot";
      };

    makeSuspendCommand = {
      hostAddress,
      sshKeyPath,
    }:
      makeSystemCtlPowerActionViaSsh {
        inherit hostAddress sshKeyPath;
        method = "suspend";
      };

    makeHibernateCommand = {
      hostAddress,
      sshKeyPath,
    }:
      makeSystemCtlPowerActionViaSsh {
        inherit hostAddress sshKeyPath;
        method = "hibernate";
      };

    polkitExtraConfig = ''
      polkit.addRule(function(action, subject) {
          if ((subject.user == "${user}") &&
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
