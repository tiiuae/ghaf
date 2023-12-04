# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  ...
}: let
  tcp-ssh =
    pkgs.writeShellScript
    "tcp-ssh"
    ''

      # Check if two arguments (HOST and PORT) are provided
      if [ $# -ne 2 ]; then
        echo "Usage: $0 <HOST> <PORT>"
        exit 1
      fi

      HOST="$1"
      PORT="$2"
      PID_FILE="''${PID_PATH:-./}tcp-ssh-$PORT.pid"

      # Stop any running tcp-ssh tunnel instances for the same tcp port
      if [ -f "$PID_FILE" ]; then
          # TODO Killing PID(s) in a file, potential for misuse
          ${pkgs.procps}/bin/pkill -F "$PID_FILE"
          rm "$PID_FILE"
      fi

      # Start tcp tunnel without shell in background mode
      # Opens a TCP tunnel from localhost to HOST:PORT
      # TODO Using ghaf waypipe-ssh default ssh key which is public and not secure
      ${pkgs.openssh}/bin/ssh -N \
           -i /run/waypipe-ssh/id_ed25519 \
           -o StrictHostKeyChecking=no \
           -o ExitOnForwardFailure=yes \
           -L $PORT:127.0.0.1:$PORT $HOST &
      # Catch the last command process (ssh) PID
      PID="$!"

      # Sleep for a second to verify connection does not die immediately
      sleep 1

      # Check if the connection ssh process with PID is still up
      if [ -n "$(${pkgs.procps}/bin/ps -p $PID -o pid=)" ]
      then
        echo "TCP tunnel over ssh to $HOST:$PORT established."
        # Save the PID to a file
        echo $PID > $PID_FILE
      else
        echo "Failed to connect to $HOST:$PORT."
      fi
    '';
in
  stdenvNoCC.mkDerivation {
    name = "tcp-ssh";

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp ${tcp-ssh} $out/bin/tcp-ssh
    '';

    meta = with lib; {
      description = "Helper script making tcp pipes over ssh";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
