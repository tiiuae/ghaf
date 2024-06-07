# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  ...
}: {
  name = "appflowy";
  packages = [pkgs.appflowy];
  macAddress = "02:00:00:03:08:01";
  ramMb = 512;
  cores = 1;
  extraModules = [
    {
      hardware.opengl.enable = true;
      time.timeZone = config.time.timeZone;
    }
  ];
}
