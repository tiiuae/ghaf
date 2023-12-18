# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    #TODO do the pci pass throughs need to be exposed here
    # They can be included in the Jetson-orin and the namespace
    # will be available to the user
    ./agx-netvm-wlan-pci-passthrough.nix
    ./format-module.nix
    ./jetson-orin.nix
    ./nx-netvm-ethernet-pci-passthrough.nix
  ];
}
