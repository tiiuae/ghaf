# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2022 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

#
# Don't work due to "new" VMs implementation restrictions 

{ config ? import ../../../spectrum/nix/eval-config.nix {} }:

import ../../../spectrum/vm/make-vm.nix { inherit config; } {
  providers.net = [ "netvm" ];
  run = config.pkgs.pkgsStatic.callPackage (
    { writeScript, bash, usbutils }:
    writeScript "run-lola-run" ''
      #!/bin/execlineb -P

      foreground { sh -c "cd /run && nohup /usr/bin/__i &" }

      if { /etc/mdev/wait network-online }
      ${bash}/bin/bash 
    ''
  ) { };
}
