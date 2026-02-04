# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./verity-repart.nix;

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
            MakeDirectories = toString [
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

        "40-swap" = {
          repartConfig = {
            Type = "swap";
            Format = "swap";
            Label = "swap";
            UUID = "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f";
          }
          // (
            if config.ghaf.storage.encryption.enable then
              {
                Encrypt = "key-file";
                # Since the partition is pre-encrypted, it doesn't compress well
                # (compressed size ~= initial size) and takes up a large portion
                # of the image file.
                # Make the initial swap small and expand it later on the device
                SizeMinBytes = "64M";
                SizeMaxBytes = "64M";
                # Free space to expand on device
                PaddingMinBytes = "8G";
                PaddingMaxBytes = "8G";
              }
            else
              {
                SizeMinBytes = "8G";
                SizeMaxBytes = "8G";
              }
          );
        };

        # Persistence partition.
        "50-persist" = {
          repartConfig = {
            Type = "linux-generic";
            Label = "persist";
            Format = "btrfs";
            SizeMinBytes = "500M";
            MakeDirectories = toString [
              "/storagevm"
            ];
            UUID = "20936304-3d57-49c2-8762-bbba07edbe75";
            # When Encrypt is "key-file" and the key file isn't specified, the
            # disk will be LUKS formatted with an empty passphrase
            Encrypt = lib.mkIf config.ghaf.storage.encryption.enable "key-file";

            # Factory reset option will format this partition, which stores all
            # the system & user state.
            FactoryReset = "yes";
          };
        };
      };
    };
  };
}
