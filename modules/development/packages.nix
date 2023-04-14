# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # For lspci:
    pciutils

    # For lsusb:
    usbutils

    # Useful in NetVM
    ethtool

    # Basic monitors
    htop
    iftop
    iotop

    traceroute
    dig
  ];
}
