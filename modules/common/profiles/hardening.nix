# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.hardening;
  has_host = builtins.hasAttr "host" config.ghaf;
  has_secureBoot = builtins.hasAttr "secureboot" config.ghaf.host;
  has_guest = builtins.hasAttr "guest" config.ghaf;
in {
  options.ghaf.profiles.hardening = {
    enable = lib.mkEnableOption "hardened profile";
  };
  imports = [../../hardware/x86_64-generic/kernel/hardening.nix];

  config = lib.mkIf cfg.enable {
    ghaf =
      {}
      // lib.optionalAttrs has_host {
        host =
          {
            # Kernel hardening
            kernel.hardening = {
              enable = false;
              usb.enable = false;
              debug.enable = false;
              virtualization.enable = false;
              networking.enable = false;
              inputdevices.enable = false;
              hypervisor.enable = false;
            };
          }
          # Enable secure boot in the host configuration
          // (
            if has_secureBoot
            then {secureboot.enable = true;}
            else {}
          );
      }
      // lib.optionalAttrs has_guest {
        guest = {
          # Kernel hardening
          kernel.hardening = {
            enable = false;
            graphics.enable = false;
          };
        };
      };
  };
}
