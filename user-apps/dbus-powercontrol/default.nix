# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# This package does nothing more than generates a pair of SSH keys and
# puts them into the /nix/store/. This package is only used in GUIvm
# and APPvms and is needed for passwordless ssh access which is required
# by waypipe package.
# I realize that this is not right, and from the security perspective it
# looks even worse, but this is an intermediate step, and in nearest future
# we completely get rid of SSH for proxying Wayland protocol.
{ stdenv
, pkgs
, lib
, dbus
, ...
}:
let
  dbusSend = "${dbus}/bin/dbus-send";
  hostSocket = "unix:path=/tmp/ssh_dbus.sock";
  busName = "org.freedesktop.login1";
  objectPath = "/org/freedesktop/login1";
  interface = "org.freedesktop.login1.Manager";

  makeDbusSendScript = { method }:
    pkgs.writeShellScript
      "${method}-host"
      (''${dbusSend} --bus=${hostSocket} --print-reply --dest=${busName} ${objectPath} "${interface}.${method}" boolean:true'');
  
  powerOffShellScript = makeDbusSendScript{ method = "PowerOff"; };
  rebootShellScript = makeDbusSendScript{ method = "Reboot"; };
  suspendShellScript = makeDbusSendScript{ method = "Suspend"; };
  hibernateShellScript = makeDbusSendScript{ method = "Hibernate"; };

in stdenv.mkDerivation {
  name = "dbus-powercontrol";

  nativeBuildInputs = [ dbus ];
  phases = [ "installPhase" ];

  powerOffCommand = "${powerOffShellScript}";
  rebootCommand = "${rebootShellScript}";
  suspendCommand = "${suspendShellScript}";
  hibernateCommand = "${hibernateShellScript}";

  installPhase = ''
    mkdir -p $out/bin;
    cp ${powerOffShellScript} $out/bin/host-poweroff;
    cp ${rebootShellScript} $out/bin/host-reboot;
    cp ${suspendShellScript} $out/bin/host-suspend;
    cp ${hibernateShellScript} $out/bin/host-hibernate;
  '';

  meta = with lib; {
    description = "Scripts for host power control";
    platforms = dbus.meta.platforms.linux;
  };
}
