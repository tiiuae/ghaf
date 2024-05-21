# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "rm-linux-bootmgrs";
  text = ''
    for id in ''$(efibootmgr | grep Linux | awk 'NR > 0 {print ''$1}' | cut -c 5-8)
    do
      sudo efibootmgr -q -b "''${id}" -B
    done
  '';
  meta = with lib; {
    description = "Helper script for removing all Linux Boot Manager entries from UEFI Boot order list";
  };
}
