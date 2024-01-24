# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  toplevelDrv,
  disko,
  diskoConfig,
}:
pkgs.substituteAll {
  dir = "bin";
  isExecutable = true;

  buildInputs = with pkgs; [nix nixos-install-tools disko];

  pname = "ghaf-installer";
  src = ./installer.sh;
  inherit (pkgs) runtimeShell;
  inherit toplevelDrv diskoConfig;
}
