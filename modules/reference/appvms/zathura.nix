# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Zathura PDF Viewer App VM
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.zathura;
in
{
  _file = ./zathura.nix;

  options.ghaf.reference.appvms.zathura = {
    enable = lib.mkEnableOption "Zathura PDF Viewer App VM";
  };

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.appvm.vms.zathura = {
      enable = lib.mkDefault true;
      name = "zathura";
      borderColor = "#122263";

      applications = [
        {
          name = "PDF Viewer";
          description = "Isolated PDF Viewer";
          packages = [ pkgs.zathura ];
          icon = "document-viewer";
          command = "zathura";
        }
      ];

      vtpm = {
        enable = lib.mkDefault true;
        runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
        basePort = 9160;
      };

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "zathura";
        ramMb = 512;
        cores = 1;
        bootPriority = "low";
        borderColor = "#122263";
        vtpm = {
          enable = lib.mkDefault true;
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
                ghaf.reference.programs.zathura.enable = lib.mkDefault true;
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
    };
  };
}
