# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  ...
}: {
  name = "slack";
  packages = [pkgs.slack];
  macAddress = "02:00:00:00:00:0A";
  ramMb = 1024;
  cores = 1;
  extraModules = [
    {
      time.timeZone = config.time.timeZone;
    }
  ];
  borderColor = "#4A154B";
}
