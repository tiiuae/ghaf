# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    disko-debug-partition.imports = [
      inputs.disko.nixosModules.disko
      ./definitions.nix
      ./repart-common.nix
      ./disko-debug-partition.nix
      ./btrfs-postboot.nix
    ];
    verity-release-partition.imports = [
      ./definitions.nix
      ./repart-common.nix
      ./verity-partition.nix
      ./verity-repart.nix
      ./verity-sysupdate.nix
      ./btrfs-postboot.nix
    ];
  };
}
