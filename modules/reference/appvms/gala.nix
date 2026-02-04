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

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.appvm.vms.gala = {
      enable = lib.mkDefault true;
      name = "gala";
      borderColor = "#027d7b";

      applications = [
        {
          name = "GALA";
          description = "Secure Android-in-the-Cloud";
          packages = [ pkgs.gala ];
          icon = "distributor-logo-android";
          command = "gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        }
      ];

      vtpm = {
        enable = true;
        runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
        basePort = 9140;
      };

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "gala";
        ramMb = 1536;
        cores = 2;
        bootPriority = "low";
        borderColor = "#027d7b";
        vtpm = {
          enable = true;
          runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
          basePort = 9140;
        };
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
