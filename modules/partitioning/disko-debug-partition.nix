# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#
# This partition scheme is used for development & debug systems.
#
# First two partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP : (500M) Kernel and initrd
#
# The third partition is a container for LVM, optionally encrypted with LUKS.
# LVM is used to create logical volumes for root, swap and persist.
#
# When deferred encryption is enabled, the image is created WITHOUT LUKS
# encryption initially. Encryption is applied on first boot when the user
# provides credentials, converting the layout to: LUKS → LVM → LVs
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
  _file = ./disko-debug-partition.nix;

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
                luks =
                  let
                    # Plain LVM content without LUKS wrapper
                    plainLvmContent = {
                      type = "lvm_pv";
                      vg = "pool";
                    };
                    # LUKS-wrapped LVM content
                    encryptedLvmContent = {
                      type = "luks";
                      name = "crypted";
                      askPassword = false;
                      initrdUnlock = false;
                      settings = {
                        keyFile = "${defaultPassword}";
                      };
                      content = plainLvmContent;
                    };
                  in
                  {
                    size = "100%";
                    priority = 3;
                    name = "luks";
                    content =
                      if config.ghaf.storage.encryption.enable && !config.ghaf.storage.encryption.deferred then
                        encryptedLvmContent
                      else
                        plainLvmContent;
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
                  resumeDevice = true; # resume from hibernation from this device
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
                # For deferred encryption, start with full size (will be extended after encryption)
                # For immediate encryption, start with 2G (will be extended by btrfs-postboot)
                size = "2G";
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
