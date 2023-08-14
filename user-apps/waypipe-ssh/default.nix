# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# This package does nothing more than generates a pair of SSH keys and
# puts them into the /nix/store/. This package is only used in GUIvm
# and APPvms and is needed for passwordless ssh access which is required
# by waypipe package.
# I realize that this is not right, and from the security perspective it
# looks even worse, but this is an intermediate step, and in nearest future
# we completely get rid of SSH for proxying Wayland protocol.
{
  stdenv,
  pkgs,
  lib,
  ...
}:
stdenv.mkDerivation {
  name = "waypipe-ssh";

  buildInputs = [pkgs.openssh];

  phases = ["buildPhase" "installPhase"];

  buildPhase = ''
    echo -e "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -o -a 100 -t ed25519 -f waypipe-ssh -C ""
  '';

  installPhase = ''
    mkdir -p $out/keys
    install ./waypipe-ssh $out/keys
    install ./waypipe-ssh.pub $out/keys
  '';

  meta = with lib; {
    description = "Helper script for launching Waypipe";
    platforms = [
      "x86_64-linux"
    ];
  };
}
