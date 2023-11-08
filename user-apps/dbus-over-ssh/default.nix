# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  ...
}: let
  vmForwardedHostSessionSocketFile = "/tmp/host_session_dbus.sock";
  vmForwardedHostSessionSocket = "unix:path=${vmForwardedHostSessionSocketFile}";

  vmForwardedHostSystemSocketFile = "/tmp/host_system_dbus.sock";
  vmForwardedHostSystemSocket = "unix:path=${vmForwardedHostSystemSocketFile}";

  hostDbusSessionAddress = "/run/user/1000/bus";
  hostDbusSystemAddress = "/run/dbus/system_bus_socket";

  hostSshdConfig = "StreamLocalBindUnlink yes";
  hostIp = "192.168.101.2";

  vmEstablishDbusConnectionViaSsh = "${pkgs.openssh}/bin/ssh \\
    -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh \\
    -o StrictHostKeyChecking=no \\
    -NT \\
    -o ServerAliveInterval=60 \\
    -o ExitOnForwardFailure=yes \\
    -L ${vmForwardedHostSessionSocketFile}:${hostDbusSessionAddress} \\
    -L ${vmForwardedHostSystemSocketFile}:${hostDbusSystemAddress} \\
    ghaf@${hostIp}";

  vmEstablishDbusConnectionViaSshScript = pkgs.writeShellScript "establishDbusConnection" vmEstablishDbusConnectionViaSsh;
in
  stdenv.mkDerivation {
    name = "dbus-over-ssh";

    nativeBuildInputs = [pkgs.dbus pkgs.openssh];

    host = {
      sshdConfigExtra = hostSshdConfig;
    };

    vm = {
      establishDbusConnectionViaSshScript = vmEstablishDbusConnectionViaSshScript;
      forwardedHostSystemSocket = vmForwardedHostSystemSocket;
    };

    installPhase = ''
      mkdir -p $out/bin;
      cp ${vmEstablishDbusConnectionViaSshScript} $out/bin/establish-dbus-connection.sh;
    '';

    meta = with lib; {
      description = "Scripts for establishing DBUS connection between the host and VMs";
      platforms = dbus.meta.platforms.linux;
    };
  }
