# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.hardening;
in {
  options.ghaf.profiles.hardening = {
    enable = lib.mkEnableOption "hardened profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      host = {
        # Enable some security features in the host configuration
        secureboot.enable = true;

        # Kernel hardening
        kernel.hardening.enable = true;
        kernel.hardening.usb.enable = true;
        kernel.hardening.debug.enable = true;
        kernel.hardening.virtualization.enable = true;
        kernel.hardening.networking.enable = true;
        kernel.hardening.inputdevices.enable = true;
        kernel.hardening.hypervisor.enable = true;
      };

      guest = {
        # Kernel hardening
        kernel.hardening.enable = true;
        kernel.hardening.graphics.enable = true;
      };
    };
  };
}
