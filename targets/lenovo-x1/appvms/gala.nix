# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: {
  name = "gala";
  packages = [pkgs.gala-app];
  macAddress = "02:00:00:03:06:01";
  ramMb = 1536;
  cores = 2;
  extraModules = [
    {
      time.timeZone = "Asia/Dubai";
    }
  ];
  borderColor = "#33ff57";
}
