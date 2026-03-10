# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./usb/external-devices.nix
    ./devices.nix
    ./input.nix
    ./kernel.nix
    ./qemu.nix
    ./tpm-endorsement.nix
  ];
}
