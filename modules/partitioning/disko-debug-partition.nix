# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#
# This partition scheme is used for development & debug systems. It contains
# four partitions.
#
# First two partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP-A : (500M) Kernel and initrd
#
# Which is followed by the data partitions:
# - root : Root partition which contains the Nix store
# - persist : Persistence partition for system & user data
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.partitioning.disko;
  inherit (config.ghaf.partitions) definition;
in
{
  options.ghaf.partitioning.disko = {
    enable = lib.mkEnableOption "the disko partitioning scheme";

    imageBuilder.compression = lib.mkOption {
      type = lib.types.enum [
        "none"
        "zstd"
      ];
      description = "Compression algorithm used for the install image";
      default = "zstd";
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.ghafImage = config.system.build.diskoImages;
    disko = {
      imageBuilder = {
        extraPostVM = lib.mkIf (cfg.imageBuilder.compression == "zstd") ''
          ${pkgs.zstd}/bin/zstd --compress $out/*raw
          rm $out/*raw
        '';
      };
      devices = {
        disk = {
          disk1 = {
            type = "disk";
            # Our root is 64G (defined in ./definitions.nix)
            # FIXME: make this value derived from root+esp sizes
            imageSize = "70G";
            content = {
              type = "gpt";
              partitions = {
                # FIXME: would we really need this old compatibility stuff?
                # The ef02 partition type, identified by the GUID partition table (GPT) tool gdisk, is a BIOS Boot Partition.
                # It's a small, ~1-2MB partition without a filesystem that holds parts of the GRUB bootloader when booting a non-UEFI system from a GPT-partitioned disk.
                # This partition is necessary for GRUB to function in BIOS mode on a GPT disk,
                # providing a place to store its core files that wouldn't fit in the post-MBR reserved space.
                esp = {
                  name = "ESP";
                  inherit (definition.esp) size label;
                  type = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"; # UUID PartType of ESP
                  content = {
                    type = "filesystem";
                    format = definition.esp.fileSystem;
                    mountpoint = definition.esp.mountPoint;
                    mountOptions = [
                      "umask=0077"
                      "nofail"
                    ];
                  };
                  priority = 2;
                };
                root = {
                  inherit (definition.root) size label;
                  type = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"; # x86-64 root partType UUID from https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
                  content = {
                    type = "filesystem";
                    format = definition.root.fileSystem;
                    mountpoint = definition.root.mountPoint;
                    mountOptions = [
                      "noatime"
                      "nodiratime"
                    ];
                  };
                  priority = 4;
                };
              };
            };
          };
        };
      };
    };
  };
}
