# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  imports = [
    ./partition-template.nix
    ../../boot/systemd-boot-dtb.nix
    ./jetson-orin.nix
    ./ssd-part.nix

    ./pci-passthrough-common.nix
    ./agx-netvm-wlan-pci-passthrough.nix
    ./nx-netvm-ethernet-pci-passthrough.nix

    ./ota-utils-fix.nix
    ./virtualization
  ];
}
