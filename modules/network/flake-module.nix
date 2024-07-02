# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  flake.nixosModules = {
    network-common.imports = [
      ./definition.nix
      ./common
    ];
  };
}
