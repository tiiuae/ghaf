# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial;
in
{
  imports = [
    ../appvms
    ../programs
    ../services
    ../personalize
  ];

  options.ghaf.reference.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        appvms = {
          enable = true;
          chromium-vm = true;
          gala-vm = true;
          zathura-vm = true;
          element-vm = true;
          appflowy-vm = true;
          business-vm = true;
        };

        services = {
          enable = true;
          dendrite = true;
        };

        programs = {
          windows-launcher = {
            enable = false;
            spice = false;
          };
        };

        personalize = {
          keys.enable = true;
        };

        profiles = {
          laptop-x86 = {
            enable = true;
            netvmExtraModules = [
              ../services
              ../personalize
              { ghaf.reference.personalize.keys.enable = true; }
            ];
            guivmExtraModules = [
              ../programs
              ../personalize
              { ghaf.reference.personalize.keys.enable = true; }
            ];
            inherit (config.ghaf.reference.appvms) enabled-app-vms;
          };
        };
      };
    };
  };
}
