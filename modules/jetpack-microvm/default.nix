# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./nx-netvm-ethernet-pci-passthrough.nix
    ./agx-netvm-wlan-pci-passthrough.nix
    ./agx-gpiovm-passthrough.nix
  ];
}
