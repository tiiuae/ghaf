# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./usb/internal.nix
    ./usb/external.nix
    ./usb/vhotplug.nix
    ./devices.nix
    ./kernel.nix
    ./qemu.nix
    ./shared-mem.nix
  ];
}
