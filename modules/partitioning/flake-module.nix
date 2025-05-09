# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    disko-debug-partition.imports = [
      inputs.disko.nixosModules.disko
      ./disko-debug-partition.nix
      ./btrfs-postboot.nix
    ];
    verity-release-partition.imports = [
      ./verity-partition.nix
      ./verity-repart.nix
      ./verity-sysupdate.nix
      ./btrfs-postboot.nix
    ];
  };
}
