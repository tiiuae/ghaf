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
      # Enable below option for session lock feature
      graphics = {
        #might be too optimistic to hide the boot logs
        #just yet :)
        # boot.enable = lib.mkForce true;
        labwc = {
          autolock.enable = lib.mkForce true;
          autologinUser = lib.mkForce null;
        };
      };

      virtualization.microvm.appvm = {
        enable = true;
        vms = {
          chrome.enable = true;
          gala.enable = true;
          zathura.enable = true;
          comms.enable = true;
          business.enable = true;
        };
      };

      reference = {
        appvms.enable = true;

        services = {
          enable = true;
          dendrite = true;
          proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
          google-chromecast = true;
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
          };
        };
      };
    };
  };
}
