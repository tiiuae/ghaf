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

      # The ids-vm MiTM tooling uses a committed development CA and a fixed web
      # UI password: it must never ship in a release image.
      #
      # global-config carries the signal to every guest: idsvm-base turns it
      # into the ids-vm's own mitmproxy.enable, and appvm-base uses it to put
      # the mitm CA in each app VM's trust store. Setting the guest option
      # directly here would instead collide with idsvm-base's definition.
      global-config.idsvm.mitmproxy.enable = lib.mkForce config.ghaf.profiles.debug.enable;

      virtualization.microvm = {
        idsvm = {
          enable = lib.mkForce config.ghaf.profiles.debug.enable;
          # Mirrors the signal for the host-side readers (givc's idsExtraArgs,
          # the chrome MitmWebUI shortcut). The proxy service itself is gated on
          # being the ids-vm, so this does not materialize it on the host.
          mitmproxy.enable = lib.mkForce config.ghaf.profiles.debug.enable;
          evaluatedConfig = config.ghaf.profiles.laptop-x86.idsvmBase.extendModules {
            modules = lib.ghaf.vm.applyVmConfig {
              inherit config;
              vmName = "idsvm";
            };
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
