# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  inherit (pkgs.stdenv.hostPlatform) efiArch;
in
{

  config = lib.mkIf cfg.enable {
    image.repart = {
      name = "ghaf";
      version = "0.0.1";

      partitions = {
        "00-esp" = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = 
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source = 
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            SizeMinBytes = "64M";
            UUID = "null";
          };
        };

        # Verity tree for the Nix store.
        "10-root-verity-a" = {
          repartConfig = {
            Type = "root-verity";
            Label = "root-verity-a";
            Verity = "hash";
            VerityMatchKey = "root";
            Minimize = "best";
          };
        };

        # Nix store.
        "11-root-a" = {
          storePaths = [ config.system.build.toplevel ];
          repartConfig = {
            Type = "root";
            Label = "root-a";
            Format = "erofs";
            Minimize = "best";
            Verity = "data";
            VerityMatchKey = "root";
            # Create directories needed for nixos activation, as these cannot be
            # created on a read-only filesystem.
            MakeDirectories = builtins.toString [
              "/bin"
              "/boot"
              "/dev"
              "/etc"
              "/home"
              "/lib"
              "/lib64"
              "/mnt"
              "/nix"
              "/opt"
              "/persist"
              "/proc"
              "/root"
              "/run"
              "/srv"
              "/sys"
              "/tmp"
              "/usr"
              "/var"
            ];
          };
        };

        # 'B' blank partitions.
        "20-root-verity-b" = {
          repartConfig = {
            Type = "linux-generic";
            SizeMinBytes = "64M";
            SizeMaxBytes = "64M";
            Label = "_empty";
            ReadOnly = 1;
          };
        };
        "21-root-b" = {
          repartConfig = {
            Type = "linux-generic";
            SizeMinBytes = "512M";
            SizeMaxBytes = "512M";
            Label = "_emptyb";
            ReadOnly = 1;
          };
        };

        # Persistence partition.
        "50-persist" = {
          repartConfig = {
            Type = "linux-generic";
            Label = "persist";
            Format = "btrfs";
            SizeMinBytes = "3G";
            MakeDirectories = builtins.toString [
              "/storagevm"
            ];
            UUID = "20936304-3d57-49c2-8762-bbba07edbe75";

            # Factory reset option will format this partition, which stores all
            # the system & user state.
            FactoryReset = "yes";
          };
        };
      };
    };
  };
}
