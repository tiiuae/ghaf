# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  zathura = {
    ramMb = 512;
    cores = 1;
    bootPriority = "low";
    borderColor = "#122263";
    vtpm = {
      enable = true;
      runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
      basePort = 9160;
    };
    applications = [
      {
        name = "PDF Viewer";
        description = "Isolated PDF Viewer";
        packages = [ pkgs.zathura ];
        icon = "document-viewer";
        command = "zathura";
        extraModules = [
          {
            imports = [ ../programs/zathura.nix ];
            ghaf.reference.programs.zathura.enable = true;
          }
        ];
      }
    ];

    extraModules = [
      {
        # This vm should be stateless so nothing stored between boots
        ghaf.storagevm.enable = lib.mkForce false;

        # Handle PDF and image open requests
        ghaf.xdghandlers = {
          pdf = true;
          image = true;
        };
      }
    ];
  };
}
