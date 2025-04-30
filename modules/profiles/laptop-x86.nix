# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.laptop-x86;
in
{
  options.ghaf.profiles.laptop-x86 = {
    enable = lib.mkEnableOption "Enable the basic x86 laptop config";

    netvmExtraModules = lib.mkOption {
      description = ''
        List of additional modules to be passed to the netvm.
      '';
      default = [ ];
    };

    guivmExtraModules = lib.mkOption {
      description = ''
        List of additional modules to be passed to the guivm.
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {

    ghaf = {
      # Hardware definitions
      hardware = {
        x86_64.common.enable = true;
        tpm2.enable = true;
        usb = {
          internal.enable = true;
          external.enable = true;
          vhotplug.enable = true;
        };
      };

      # Virtualization options
      virtualization = {
        microvm-host = {
          enable = true;
          networkSupport = true;
          sharedVmDirectory = {
            enable = true;
          };
        };

        microvm = {
          netvm = {
            enable = true;
            wifi = true;
            extraModules = cfg.netvmExtraModules;
          };

          adminvm = {
            enable = true;
          };

          idsvm = {
            enable = false;
            mitmproxy.enable = false;
          };

          guivm = {
            enable = true;
            extraModules = cfg.guivmExtraModules;
          };

          audiovm = {
            enable = true;
            audio = true;
          };
        };
      };

      # Enable givc
      givc.enable = true;
      givc.debug = false;

      host = {
        networking.enable = true;
      };

      # Shared memory configuration
      shm.enable = true;
      shm.gui = true;
    };
  };
}
