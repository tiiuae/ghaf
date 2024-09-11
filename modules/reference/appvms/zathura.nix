# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  config,
  ...
}:
{
  name = "zathura";
  packages = [ pkgs.zathura ];
  macAddress = "02:00:00:03:07:01";
  ramMb = 512;
  cores = 1;
  extraModules = [
    {
      imports = [ ../programs/zathura.nix ];
      time.timeZone = config.time.timeZone;
      ghaf = {
        reference.programs.zathura.enable = true;

        givc.appvm = {
          enable = true;
          name = lib.mkForce "zathura-vm";
          applications = lib.mkForce ''{"zathura": "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/zathura"}'';
        };

        #this vm should be stateless so nothing stored between boots.
        storagevm.enable = lib.mkForce false;
      };
      # Enable printer service
      ghaf.services.printer = {
        enable = true;
        name = "zathura";
      };
    }
  ];
  borderColor = "#122263";
}
