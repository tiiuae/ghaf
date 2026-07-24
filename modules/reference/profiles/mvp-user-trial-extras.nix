# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
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
        # The ids-vm MiTM tooling uses a committed development CA and a fixed
        # web UI password: it must never ship in a release image.
        idsvm = {
          enable = lib.mkForce config.ghaf.profiles.debug.enable;
          # mitmproxy is enabled inside the ids-vm guest via extendModules
          # below; enabling it here as well would materialize the proxy
          # service in the host evaluation too.
          evaluatedConfig = config.ghaf.profiles.laptop-x86.idsvmBase.extendModules {
            modules = [
              { ghaf.virtualization.microvm.idsvm.mitmproxy.enable = true; }
            ];
          };
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
