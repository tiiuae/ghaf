# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.mvp-user-trial;
in {
  imports = [
    ../reference/appvms
    ../reference/programs
    ../reference/services
  ];

  options.ghaf.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference.appvms = {
        enable = true;
        chromium-vm = true;
        gala-vm = true;
        zathura-vm = true;
        element-vm = true;
        appflowy-vm = true;
      };

      reference.services = {
        enable = true;
        dendrite = true;
      };

      reference.programs = {
        windows-launcher = {
          enable = true;
          spice = true;
        };
      };
    };
  };
}
