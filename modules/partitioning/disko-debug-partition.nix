# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
in
{
  options.ghaf.partitioning.disko = {
    enable = lib.mkEnableOption "Enable the disko partitioning scheme";

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
    disko = {
      imageBuilder = {
        extraPostVM = lib.mkIf (cfg.imageBuilder.compression == "zstd") ''
          ${pkgs.zstd}/bin/zstd --compress $out/*raw
          rm $out/*raw
        '';
      };
      devices = {
        disk.disk1 = {
          type = "disk";
          imageSize = "60G";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                name = "boot";
                size = "1M";
                type = "EF02";
                priority = 1; # Needs to be first partition
              };
              esp = {
                name = "ESP";
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "umask=0077"
                    "nofail"
                  ];
                };
                priority = 2;
              };
              swap = {
                size = "12G";
                type = "8200";
                content = {
                  type = "swap";
                  resumeDevice = true; # resume from hiberation from this device
                  randomEncryption = true;
                };
                priority = 3;
              };
              root = {
                size = "40G";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                  ];
                };
                priority = 4;
              };
              persist = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "btrfs";
                  mountpoint = "/persist";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
