# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  runtimeShell,
  imagePath,
}:
pkgs.substituteAll {
  dir = "bin";
  isExecutable = true;

  pname = "ghaf-installer";
  src = ./ghaf-installer.sh;
  inherit runtimeShell imagePath;
}
