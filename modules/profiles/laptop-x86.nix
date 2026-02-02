# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.laptop-x86;
in
{
  options.ghaf.profiles.laptop-x86 = {
    enable = lib.mkEnableOption "Enable the basic x86 laptop config";

    netvmExtensions = lib.mkOption {
      description = ''
        List of additional modules to be passed to the netvm via extensions registry.
      '';
      default = [ ];
    };

    guivmExtensions = lib.mkOption {
      description = ''
        List of additional modules to be passed to the guivm via extensions registry.
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
        passthrough = {
          vhotplug.enable = true;
          usbQuirks.enable = true;

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
          };

          audiovm = {
            enable = true;
            audio = true;
          };

          # Extensions registry for VM configuration
          extensions = {
            netvm = cfg.netvmExtensions;
            guivm = cfg.guivmExtensions;
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
