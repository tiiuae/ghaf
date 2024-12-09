# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  config,
  ...
}:
let
  name = "gala";
  hostsEntries = import ../../common/networking/hosts-entries.nix;
  vmname = name + "-vm";
in
{
  inherit name;
  packages = [ pkgs.gala-app ];
  macAddress = "02:00:00:03:06:01";
  internalIP = hostsEntries.ipByName vmname;
  ramMb = 1536;
  cores = 2;
  extraModules = [
    {
      time.timeZone = config.time.timeZone;
      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "gala-vm";
        applications = [
          {
            name = "gala";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
          }
        ];
      };
    }
  ];
  borderColor = "#027d7b";
}
