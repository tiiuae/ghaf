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

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable and evaluatedConfig at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.zathura = {
      enable = lib.mkDefault true;

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "zathura";
        mem = 512;
        vcpu = 1;
        bootPriority = "low";
        borderColor = "#122263";
        vtpm.enable = lib.mkDefault true;
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
