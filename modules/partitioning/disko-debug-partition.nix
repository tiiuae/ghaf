# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#
# This partition scheme is used for development & debug systems. It contains
# three partitions.
#
# First two partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP-A : (500M) Kernel and initrd
#
# The third partition is a container for LVM, optionally encrypted with LUKS.
# LVM is used to create logical volumes for root, swap and persist.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.partitioning.disko;
  defaultPassword = pkgs.writeTextFile {
    name = "disko-default-password";
    text = "";
  };
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
            imageSize = "70G";
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
                luks = {
                  size = "100%";
                  priority = 3;
                  content =
                    if config.ghaf.storage.encryption.enable then
                      {
                        type = "luks";
                        name = "crypted";
                        initrdUnlock = false;
                        askPassword = false;
                        settings = {
                          keyFile = "${defaultPassword}";
                        };
                        content = {
                          type = "lvm_pv";
                          vg = "pool";
                        };
                      }
                    else
                      {
                        type = "lvm_pv";
                        vg = "pool";
                      };
                };
              };
            };
          };
        };
        lvm_vg = {
          pool = {
            type = "lvm_vg";
            lvs = {
              swap = {
                size = "12G";
                content = {
                  type = "swap";
                  resumeDevice = true; # resume from hiberation from this device
                  randomEncryption = !config.ghaf.storage.encryption.enable;
                };
              };
              root = {
                size = "50G";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                  ];
                };
              };
              persist = {
                size = if config.ghaf.storage.encryption.enable then "2G" else "100%";
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
