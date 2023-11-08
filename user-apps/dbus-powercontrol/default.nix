# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  dbus,
  ...
}: let
  dbusSend = "${dbus}/bin/dbus-send";

  busName = "org.freedesktop.login1";
  objectPath = "/org/freedesktop/login1";
  interface = "org.freedesktop.login1.Manager";

  systemSocket = pkgs.dbus-over-ssh.vm.forwardedHostSystemSocket;

  makeDbusSendScript = {
    dbusSocket,
    method,
  }:
    pkgs.writeShellScript
    "${method}-host"
    ''${dbusSend} --bus=${dbusSocket} --print-reply --dest=${busName} ${objectPath} "${interface}.${method}" boolean:false'';

  powerOffMemberName = "PowerOff";
  rebootMemberName = "Reboot";
  suspendMemberName = "Suspend";
  hibernateMemberName = "Hibernate";

  powerOffShellScript = makeDbusSendScript {
    dbusSocket = systemSocket;
    method = powerOffMemberName;
  };
  rebootShellScript = makeDbusSendScript {
    dbusSocket = systemSocket;
    method = rebootMemberName;
  };
  suspendShellScript = makeDbusSendScript {
    dbusSocket = systemSocket;
    method = suspendMemberName;
  };
  hibernateShellScript = makeDbusSendScript {
    dbusSocket = systemSocket;
    method = hibernateMemberName;
  };

  makeDbusRule = {memberName}: ''
    <allow
      send_destination="${busName}"
      send_interface="${interface}"
      send_member="${memberName}"
    />
  '';
  powerOffDbusRule = makeDbusRule {memberName = powerOffMemberName;};
  rebootDbusRule = makeDbusRule {memberName = rebootMemberName;};
  suspendDbusRule = makeDbusRule {memberName = suspendMemberName;};
  hibernateDbusRule = makeDbusRule {memberName = hibernateMemberName;};
in
  stdenv.mkDerivation {
    name = "dbus-powercontrol";

    nativeBuildInputs = [pkgs.dbus-over-ssh];
    phases = ["installPhase"];

    powerOffCommand = "${powerOffShellScript}";
    rebootCommand = "${rebootShellScript}";
    suspendCommand = "${suspendShellScript}";
    hibernateCommand = "${hibernateShellScript}";

    dbusConfig = ''
      <busconfig>
        <policy context="default">
          ${powerOffDbusRule}
          ${rebootDbusRule}
          ${suspendDbusRule}
          ${hibernateDbusRule}
        </policy>
      </busconfig>
    '';

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

    installPhase = ''
      mkdir -p $out/bin;

      cp ${powerOffShellScript} $out/bin/host-poweroff.sh;
      cp ${rebootShellScript} $out/bin/host-reboot.sh;
      cp ${suspendShellScript} $out/bin/host-suspend.sh;
      cp ${hibernateShellScript} $out/bin/host-hibernate.sh;
    '';

    meta = with lib; {
      description = "Scripts for host power control";
      platforms = dbus.meta.platforms.linux;
    };
  }
