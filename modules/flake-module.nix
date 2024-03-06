# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules to be exported from Flake
#
_: {
  flake.nixosModules = {
    common.imports = [./common];
    desktop.imports = [./desktop];
    host.imports = [./host];
    jetpack.imports = [./jetpack];
    jetpack-microvm.imports = [./jetpack-microvm];
    lanzaboote.imports = [./lanzaboote];
    microvm.imports = [./microvm];
    polarfire.imports = [./polarfire];
  };
}
