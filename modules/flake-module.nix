# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules to be exported from Flake
#
_: {
  flake.nixosModules = {
    common = import ./common;
    desktop = import ./desktop;
    host = import ./host;
    jetpack = import ./jetpack;
    jetpack-microvm = import ./jetpack-microvm;
    lanzaboote = import ./lanzaboote;
    microvm = import ./microvm;
    polarfire = import ./polarfire;
  };
}
