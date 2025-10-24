# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (config.ghaf.partitions) definition;
in
{
  boot.initrd.systemd.repart = {
    enable = true;
    device = null; # Operate on current root device, from which system booted
  };

  systemd.repart = {
    enable = true;
    partitions = {
      # Verity tree for the Nix store.
      # (create verity partition, even if we booted from disko populated image)
      "10-root-verity-a" = {
        Type = "root-verity";
        Label = "root-verity-a";
        Verity = "hash";
        VerityMatchKey = "root";
        Minimize = "best";
      };

      # 'B' blank partitions.
      "20-root-verity-b" = {
        Type = "linux-generic";
        SizeMinBytes = "64M";
        SizeMaxBytes = "64M";
        Label = "_empty";
        ReadOnly = 1;
      };

      "21-root-b" = {
        Type = "linux-generic";
        SizeMinBytes = "512M";
        SizeMaxBytes = "512M";
        Label = "_emptyb";
        ReadOnly = 1;
      };

      "40-swap" = {
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
            PaddingMinBytes = definition.swap.size;
            PaddingMaxBytes = definition.swap.size;
          }
        else
          {
            SizeMinBytes = definition.swap.size;
            SizeMaxBytes = definition.swap.size;
          }
      );
      # Persistence partition.
      "50-persist" = {
        repartConfig = {
          Type = "linux-generic";
          Label = "persist";
          Format = "btrfs";
          SizeMinBytes = definition.persist.size;
          MakeDirectories = builtins.toString [
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
}
