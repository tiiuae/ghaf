# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  ...
}:
let
  inherit (config.ghaf.partitions) definition;
  defaultPassword = pkgs.writeTextFile {
    name = "disko-default-password";
    text = "";
  };
in
{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.repart = {
    enable = true;
    device = null; # Operate on current root device, from which system booted
    extraArgs =
      if config.ghaf.storage.encryption.enable then
        [
          "--key-file"
          defaultPassword
        ]
      else
        [ ];
  };
  # FIXME: make conditional if we have any btrfs enabled in definitions
  boot.initrd.supportedFilesystems.btrfs = true; # systemd-repart need btrfs-progs in initrd

  systemd.repart = {
    enable = true;
    partitions = {
      "10-root-a" = {
        Type = "root";
        Label = definition.root.label;
        Verity = "data";
        VerityMatchKey = "${definition.root.label}";
        SplitName = "root";
        #SizeMinBytes = definition.root.size;
        SizeMaxBytes = definition.root.size;
      };
      # Verity tree for the Nix store.
      # (create verity partition, even if we booted from disko populated image)
      "11-root-verity-a" = {
        Type = "root-verity";
        Label = "root-verity_0";
        Verity = "hash";
        VerityMatchKey = "${definition.root.label}";
        SizeMinBytes = "8G";
        SizeMaxBytes = "8G";
      };

      # 'B' blank partitions.
      "20-root-verity-b" = {
        Type = "root-verity";
        Label = "_empty";
        ReadOnly = 1;
        SizeMinBytes = "8G";
        SizeMaxBytes = "8G";
      };

      "21-root-b" = {
        Type = "root";
        SizeMaxBytes = definition.root.size;
        Label = "_empty";
        ReadOnly = 1;
      };
      "40-swap" = {
        Type = "swap";
        Format = "swap";
        Label = definition.swap.label;
        UUID = "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f";
        SizeMinBytes = definition.swap.size;
        SizeMaxBytes = definition.swap.size;
        # When Encrypt is "key-file" and the key file isn't specified, the
        # disk will be LUKS formatted with an empty passphrase
        Encrypt = if config.ghaf.storage.encryption.enable then "key-file" else "off";
      };
      # Persistence partition.
      "50-persist" = {
        Type = "linux-generic";
        Label = definition.persist.label;
        Format = "btrfs";
        SizeMinBytes = definition.persist.size;
        MakeDirectories = toString [
          "/storagevm"
        ];
        UUID = "20936304-3d57-49c2-8762-bbba07edbe75";
        # When Encrypt is "key-file" and the key file isn't specified, the
        # disk will be LUKS formatted with an empty passphrase
        Encrypt = if config.ghaf.storage.encryption.enable then "key-file" else "off";

        # Factory reset option will format this partition, which stores all
        # the system & user state.
        FactoryReset = "yes";
      };
    };
  };

  fileSystems = {
    "/persist" = {
      device =
        if config.ghaf.storage.encryption.enable then
          "/dev/mapper/persist"
        else
          "/dev/disk/by-partlabel/${definition.persist.label}";
      fsType = definition.persist.fileSystem;
      options = [
        "noatime"
        "nodiratime"
      ]; # FIXME: move options to definitions
    };
  };

  swapDevices = [
    {
      device =
        if config.ghaf.storage.encryption.enable then
          "/dev/mapper/swap"
        else
          "/dev/disk/by-partlabel/${definition.swap.label}";
      options = [ "nofail" ]; # Don't fail to boot, if swap missed. FIXME: at least unless we fully debug new partitioning
    }
  ];
}
