# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  imports = [
    ./host
    ./guest
    ./host/pkvm
    # other host hardening modules - to be defined later
  ];

  config = {
    # host kernel hardening
    ghaf.host.kernel.hardening.enable = false;
    ghaf.host.kernel.hardening.virtualization.enable = false;
    ghaf.host.kernel.hardening.networking.enable = false;
    ghaf.host.kernel.hardening.usb.enable = false;
    ghaf.host.kernel.hardening.inputdevices.enable = false;
    ghaf.host.kernel.hardening.debug.enable = false;
    # host kernel hypervisor (KVM) hardening
    ghaf.host.kernel.hardening.hypervisor.enable = false;
    # guest kernel hardening
    ghaf.guest.kernel.hardening.enable = false;
    ghaf.guest.kernel.hardening.graphics.enable = false;
    # other host hardening options - user space, etc. - to be defined later
  };
}
