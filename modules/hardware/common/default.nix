# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./usb/external-devices.nix
    ./usb/vhotplug.nix
    ./usb/quirks.nix
    ./devices.nix
    ./input.nix
    ./kernel.nix
    ./qemu.nix
  ];
}
