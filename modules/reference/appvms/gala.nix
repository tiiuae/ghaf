# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GALA App VM - Android-in-the-Cloud
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.gala;
in
{
  _file = ./gala.nix;

  options.ghaf.reference.appvms.gala = {
    enable = lib.mkEnableOption "GALA Android-in-the-Cloud App VM";
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable and evaluatedConfig at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.gala = {
      enable = lib.mkDefault true;

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "gala";
        mem = 1536;
        vcpu = 2;
        bootPriority = "low";
        borderColor = "#027d7b";
        vtpm.enable = lib.mkDefault true;
        applications = [
          {
            name = "GALA";
            description = "Secure Android-in-the-Cloud";
            packages = [ pkgs.gala ];
            icon = "distributor-logo-android";
            command = "gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
          }
        ];
      };
    };
  };
}
