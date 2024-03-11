# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
  flake.nixosModules = {
    # TODO: rename this module to what it actually does rather than what model it's for.
    # We version the disko partitiong module so that we can update it without breaking existing systems
    disko-lenovo-x1-basic-v1.imports = [
      inputs.disko.nixosModules.disko
      ./lenovo-x1-disko-basic.nix
      ./disko-basic-postboot.nix
    ];
  };
}
