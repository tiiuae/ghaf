# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.hardening;
in
{
  options.ghaf.profiles.kernel-hardening = {
    enable = lib.mkEnableOption "hardened profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
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
