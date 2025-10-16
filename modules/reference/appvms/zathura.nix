# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    bootPriority = "low";
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
        ghaf.xdghandlers = {
          pdf = true;
          image = true;
        };
        # Let systemd use default ordering for audit-rules instead of early-boot
        systemd.services.audit-rules = {
          unitConfig.DefaultDependencies = lib.mkForce true;
          before = lib.mkForce [ ];
        };
      }
    ];
  };
}
