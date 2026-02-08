# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.kernel-hardening;
  hasHost = builtins.hasAttr "host" config.ghaf;
  hasGuest = builtins.hasAttr "guest" config.ghaf;
in
{
  _file = ./kernel-hardening.nix;

  options.ghaf.profiles.kernel-hardening = {
    enable = lib.mkEnableOption "hardened profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf =
      { }
      // lib.optionalAttrs hasHost {
        host = {
          # Kernel hardening
          kernel.hardening = {
            enable = true;
            usb.enable = true;
            debug.enable = true;
            virtualization.enable = true;
            networking.enable = true;
            inputdevices.enable = true;
            hypervisor.enable = true;
          };
        };
      }
      // lib.optionalAttrs hasGuest {
        guest = {
          # Kernel hardening
          kernel.hardening = {
            enable = true;
            graphics.enable = true;
          };
        };
      };
  };
}
