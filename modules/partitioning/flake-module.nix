# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
let
  secureAbCoreModules = [
    inputs.nix-store-veritysetup-generator.nixosModules.ghaf-store-veritysetup-generator
    ./verity-volume.nix
    ./secure-update.nix
    ./boot-health.nix
  ];
in
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    disko-debug-partition.imports = [
      inputs.disko.nixosModules.disko
      ./disko-debug-partition.nix
      ./deferred-disk-encryption.nix
      ./btrfs-postboot.nix
    ];
    secure-ab-core.imports = secureAbCoreModules;
    verity-release-partition.imports = secureAbCoreModules ++ [
      ./btrfs-postboot.nix
    ];
  };
}
