# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: {
  name = "zathura";
  packages = [pkgs.zathura];
  macAddress = "02:00:00:03:07:01";
  ramMb = 512;
  cores = 1;
  extraModules = [
    {
      time.timeZone = "Asia/Dubai";
      ghaf.programs.zathura.enable = true;
    }
  ];
  borderColor = "#122263";
}
