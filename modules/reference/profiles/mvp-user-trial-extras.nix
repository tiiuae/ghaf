# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial-extras;
in
{
  imports = [ ./mvp-user-trial.nix ];

  options.ghaf.reference.profiles.mvp-user-trial-extras = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        profiles = {
          mvp-user-trial.enable = true;
        };

        programs = {
          windows-launcher = {
            enable = true;
            spice = true;
          };
        };
      };

      profiles = {
        # Enable below option for host hardening features
        # Secure Boot
        host-hardening.enable = true;
      };

      virtualization.microvm = {
        # Enable idsvm and the MiTM features
        idsvm = {
          enable = lib.mkForce true;
          mitmproxy.enable = lib.mkForce true;
        };
      };

      graphics = {
        labwc = {
          autologinUser = lib.mkForce null;
        };
      };

      # Enable audit
      security.audit.enable = lib.mkForce true;

      # host = {
      #   kernel.hardening = {
      #     enable = false;
      #     virtualization.enable = false;
      #     networking.enable = false;
      #     usb.enable = false;
      #     inputdevices.enable = false;
      #     debug.enable = false;
      #     # host kernel hypervisor (KVM) hardening
      #     hypervisor.enable = false;
      #   };
      # };
      # # guest kernel hardening
      # guest = {
      #   kernel.hardening = {
      #     enable = false;
      #     graphics.enable = false;
      #   };
      # };
    };
  };
}
