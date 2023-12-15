# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    ./partition-template.nix
    ../../boot/systemd-boot-dtb.nix
    ./jetson-orin.nix

    ./pci-passthrough-common.nix
    ./agx-netvm-wlan-pci-passthrough.nix
    ./nx-netvm-ethernet-pci-passthrough.nix

    ./ota-utils-fix.nix
    ./virtualization
  ];
}
