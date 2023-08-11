# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  runtimeShell,
  systemImgDrv,
}:
pkgs.substituteAll {
  dir = "bin";
  isExecutable = true;

  name = "ghaf-installer";
  src = ./installer.sh;
  inherit runtimeShell systemImgDrv;
}
