# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  flake.nixosModules = {
    hw-lenovo-x1.imports = [
      ./definition.nix
      ./x86_64-generic
      ./lenovo-x1
    ];
    hw-x86_64-generic.imports = [
      ./definition.nix
      ./x86_64-generic
    ];
  };
}
