# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  ...
}:
{
  name = "zathura";
  packages = [
    # Image viewer
    pkgs.pqiv
  ];
  macAddress = "02:00:00:03:07:01";
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
    }
  ];
}
