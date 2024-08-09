# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    ./partition-template.nix
    ./jetson-orin.nix

    ./pci-passthrough-common.nix

    ./ota-utils-fix.nix
    ./agx-milboard
    ./virtualization

    ./optee.nix
  ];
}
