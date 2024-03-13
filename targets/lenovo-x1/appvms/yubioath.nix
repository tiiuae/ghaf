# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: {
  name = "yubioath";
  packages = [pkgs.yubioath-flutter pkgs.pcsclite];
  macAddress = "02:00:00:03:08:01";
  ramMb = 512;
  cores = 1;
  enablePcscd = true;
  extraModules = [
    {
      hardware.opengl.enable = true;
      time.timeZone = "Asia/Dubai";
    }
  ];
}
