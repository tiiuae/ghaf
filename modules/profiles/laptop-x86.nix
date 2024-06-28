# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  powerControl = pkgs.callPackage ../../packages/powercontrol {};
  cfg = config.ghaf.profiles.laptop-x86;
in {
  imports = [
    ../desktop/graphics
    ../common
    ../host
    ../microvm
    ../hardware/x86_64-generic
    ../hardware/common
    ../hardware/definition.nix
  ];

  options.ghaf.profiles.laptop-x86 = {
    enable = lib.mkEnableOption "Enable the basic x86 laptop config";
  };

  config = lib.mkIf cfg.enable {
    security.polkit = {
      enable = true;
      extraConfig = powerControl.polkitExtraConfig;
    };

    ghaf = {
      # Hardware definitions
      hardware = {
        x86_64.common.enable = true;
        tpm2.enable = true;
        usb.internal.enable = true;
        usb.external.enable = true;
      };

      # Virtualization options
      virtualization = {
        microvm-host = {
          enable = true;
          networkSupport = true;
        };

        microvm = {
          netvm = {
            enable = true;
            wifi = true;
            extraModules = [../reference/services];
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
            extraModules = [../reference/programs];
          };

          audiovm = {
            enable = true;
            audio = true;
          };

          appvm = {
            enable = true;
            vms = config.ghaf.reference.appvms.enabled-app-vms;
          };
        };
      };

      host = {
        networking.enable = true;
        powercontrol.enable = true;
      };

      # UI applications
      profiles = {
        applications.enable = false;
      };
    };
  };
}
