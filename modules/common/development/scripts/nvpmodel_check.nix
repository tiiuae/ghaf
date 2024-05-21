# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "nvpmodel-check";
  text = ''
    # Since performance depends heavily on power mode it should be checked before performance testing.

    # This integer is given with the command, e.g. 'nvpmodel-check 3'
    ExpectedPowerModeNo="''$1"

    if hostname | grep -qw "ghaf-host"; then
        if nvpmodel | grep -q "command not found"; then
            echo -e "nvpmodel not available\ŋ"
        else
            echo -e "''$(nvpmodel -q)\n"
            ModeNo=''$(nvpmodel -q | awk -F: 'NR==2 {print ''$1}')
            if [ "''$ModeNo" -eq "''$ExpectedPowerModeNo" ]; then
                echo "Power mode check ok: ''${ModeNo}"
                exit 0
            else
                echo "Unexpected power mode detected: ''${ModeNo}"
            fi
        fi
    else
        echo -e "\nVirtual environment detected. Power mode cannot be checked."
    fi
    exit 1
  '';
  meta = with lib; {
    description = "
        Script for checking power mode of an Orin AGX/NX target.
        If executed in correct environment (ghaf-host) it gives return code 0 when the power mode number is as expected.
        Otherwise the return code is 1.
      ";
  };
}
