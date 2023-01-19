# SPDX-License-Identifier: Apache 2.0
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # For lspci:
    pciutils

    # For lsusb:
    usbutils
  ];
}
