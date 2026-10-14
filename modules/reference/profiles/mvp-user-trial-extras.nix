# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial-extras;
in
{
  _file = ./mvp-user-trial-extras.nix;

  imports = [ ./mvp-user-trial.nix ];

  options.ghaf.reference.profiles.mvp-user-trial-extras = {
    enable = lib.mkEnableOption "the mvp configuration for apps and services";
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

        services.alpaca-ollama = true;
      };

      profiles = {
        # Enable below option for host hardening features
        # Secure Boot
        host-hardening.enable = true;
      };

      virtualization.microvm = {
        idsvm = {
          enable = lib.mkForce config.ghaf.profiles.debug.enable;
          evaluatedConfig = config.ghaf.profiles.laptop-x86.idsvmBase.extendModules {
            modules = lib.ghaf.vm.applyVmConfig {
              inherit config;
              vmName = "idsvm";
            };
          };
          # Base laptop-x86 profile leaves this off; only the extras/trial
          # image turns passive monitoring on.
          passiveMonitor.enable = lib.mkForce true;
        };
      };

      virtualization.storagevm-encryption.enable = true;

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
