# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is a temporary solution for hardware detection.
#
{
  writeShellApplication,
  util-linux,
  pciutils,
  usbutils,
  dmidecode,
  alejandra,
}:
writeShellApplication {
  name = "hardware-scan";
  runtimeInputs = [
    util-linux
    pciutils
    usbutils
    dmidecode
    alejandra
  ];
  text = builtins.readFile ./hardware-scan.sh;
  meta = {
    description = "Helper script for hardware discovery and configuration file generation";
    platforms = [ "x86_64-linux" ];
  };
}
