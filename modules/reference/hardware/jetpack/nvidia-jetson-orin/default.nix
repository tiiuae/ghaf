# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    ./flash-images.nix
    ./initrd-flash.nix
    ./jetson-orin.nix
    ./pci-passthrough-common.nix
    ./virtualization
    ./optee.nix
  ];
}
