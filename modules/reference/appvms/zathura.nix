# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  ...
}:
{
  zathura = {
    ramMb = 512;
    cores = 1;
    borderColor = "#122263";
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
        ghaf.xdghandlers.enable = true;
      }
    ];
  };
}
