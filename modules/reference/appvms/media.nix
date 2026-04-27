# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Media VM - Handle PDFs, images, and video files
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.media;
in
{
  _file = ./media.nix;

  options.ghaf.reference.appvms.media = {
    enable = lib.mkEnableOption "Media VM";
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable and evaluatedConfig at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.media = {
      enable = lib.mkDefault true;

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "media";
        mem = 1024;
        vcpu = 2;
        bootPriority = "low";
        borderColor = "#122263";
        machineType = "microvm";
        vtpm.enable = lib.mkDefault true;
        extraModules = [
          {
            # This vm should be stateless so nothing stored between boots
            ghaf.storagevm.enable = lib.mkForce false;

            # Handle document, image, and video open requests
            ghaf.xdghandlers = {
              pdf.enable = true;
              image.enable = true;
              video.enable = true;
            };
          }
        ];
      };
    };
  };
}
