# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    ./partition-template.nix
    ./jetson-orin.nix

    # TODO! Disabled for 6.x kernel update, should be fixed and re-enabled!
    # ./pci-passthrough-common.nix

    ./ota-utils-fix.nix
    # TODO! Disabled for 6.x kernel update, should be fixed and re-enabled!
    # ./virtualization

    ./optee.nix
  ];
}
