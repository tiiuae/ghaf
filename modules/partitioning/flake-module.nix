# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    disko-debug-partition.imports = [
      inputs.disko.nixosModules.disko
      ./disko-debug-partition.nix
      ./disko-postboot.nix
    ];
  };
}
