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
      inputs.nix-store-veritysetup-generator.nixosModules.ghaf-store-veritysetup-generator
      (
        { pkgs, ... }:
        {
          # FIXME: Need better way for package injection
          boot.initrd.systemd.ghaf-store-veritysetup-generator.package =
            inputs.nix-store-veritysetup-generator.packages.${pkgs.hostPlatform.system}.ghaf-store-veritysetup-generator;
        }
      )
      ./verity-partition.nix
      ./verity-volume.nix
      ./verity-repart.nix
      ./verity-sysupdate.nix
      ./btrfs-postboot.nix
    ];
  };
}
