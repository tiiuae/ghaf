# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.laptop-x86;
in
{
  imports = [
    ./graphics.nix
    ../common
    ../host
    #TODO how to reference the miocrovm module here?
    #self.nixosModules.microvm
    #../microvm
    ../hardware/x86_64-generic
    ../hardware/common
    ../hardware/definition.nix
  ];

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

    enabled-app-vms = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        List of appvms to include in the Ghaf reference appvms module
      '';
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

          appvm = {
            enable = true;
            vms = cfg.enabled-app-vms;
          };
        };
      };

      # Enable givc
      givc.enable = true;
      givc.debug = false;

      host = {
        networking.enable = true;
      };
    };
  };
}
