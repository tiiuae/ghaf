# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  imports = [
    ./host
    ./guest
    ./host/pkvm
    # other host hardening modules - to be defined later
  ];

  config = {
    # host kernel hardening
    ghaf = {
      host = {
        kernel.hardening = {
          enable = false;
          virtualization.enable = false;
          networking.enable = false;
          usb.enable = false;
          inputdevices.enable = false;
          debug.enable = false;
          # host kernel hypervisor (KVM) hardening
          hypervisor.enable = false;
        };
      };
      # guest kernel hardening
      guest = {
        kernel.hardening = {
          enable = false;
          graphics.enable = false;
        };
      };
      # other host hardening options - user space, etc. - to be defined later
    };
  };
}
