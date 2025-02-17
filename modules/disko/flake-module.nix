# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    disko-basic-partition-v1.imports = [
      inputs.disko.nixosModules.disko
      ./disko-basic-partition-v1.nix
      ./disko-basic-postboot.nix
    ];

    disko-ab-partitions-v1.imports = [
      inputs.disko.nixosModules.disko
      ./disko-ab-partitions.nix
    ];
  };
}
