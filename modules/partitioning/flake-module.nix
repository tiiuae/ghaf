# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    disko-debug-partition.imports = [
      inputs.disko.nixosModules.disko
      ./disko-debug-partition.nix
      ./deferred-disk-encryption.nix
      ./btrfs-postboot.nix
    ];
    verity-release-partition.imports = [
      ./verity-partition.nix
      ./verity-volume.nix
      ./verity-repart.nix
      ./verity-sysupdate.nix
      ./btrfs-postboot.nix
    ];
  };
}
