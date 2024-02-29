# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
[
  ../../modules/development/usb-serial.nix
  {
    ghaf.development.usb-serial.enable = true;
    ghaf.profiles.debug.enable = true;
  }
  ../../modules/host/secureboot.nix
  {
    ghaf.host.secureboot.enable = false;
  }
  ../../modules/hardware/x86_64-generic/kernel/host
  {
    ghaf.host.kernel.hardening.usb.enable = false;
    ghaf.host.kernel.hardening.debug.enable = false;
  }
]
