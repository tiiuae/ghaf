# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
}:
writeShellApplication {
  name = "hardware-scan";
  runtimeInputs = [
    util-linux
    pciutils
    usbutils
    dmidecode
  ];
  text = builtins.readFile ./hardware-scan.sh;
  meta = {
    description = "Helper script for hardware discovery and configuration file generation";
  };
}
