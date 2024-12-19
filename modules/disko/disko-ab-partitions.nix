# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This partition scheme contains three common partitions and ZFS pool.
# Some partitions are duplicated for the future AB SWupdate implementation.
#
# First two partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP-A : (500M) Kernel and initrd
#
# ZFS datasets do not necessary need to have specified size and can be
# allocated dynamically. Quotas only restrict the maximum size of
# datasets, but do not reserve the space in the pool.
# The ZFS pool contains next datasets:
# - root : (30G) Root FS
# - vm-storage : (30G) Possible standalone pre-built VM images are stored here
# - reserved : (10G) Reserved dataset, no use
# - gp-storage : (50G) General purpose storage for some common insecure cases
# - recovery : (no quota) Recovery factory image is stored here
# - storagevm: (no quota) Dataset is meant to be used for StorageVM
{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  diskEncryption = config.ghaf.disk.encryption.enable;
in
{
  options = {
    ghaf.imageBuilder.compression = lib.mkOption {
      type = lib.types.enum [
        "none"
        "zstd"
      ];
      description = "Compression algorithm used for the install image";
      default = "zstd";
    };
  };
  config = {
    # TODO Keep ZFS-related parts of the configuration here for now.
    # This allows to have all config dependencies in one place and cleans
    # other targets' configs from unnecessary components.
    networking.hostId = "8425e349";
    boot = {
      initrd.availableKernelModules = [ "zfs" ];
      supportedFilesystems = [ "zfs" ];
      zfs.extraPools = [ "zfs_data" ];

      initrd.luks = mkIf diskEncryption {
        devices = {
          zfs_data = {
            device = "/dev/disk/by-partlabel/disk-disk1-zfs_data";
            crypttabExtraOpts = [ "tpm2-device=auto" ];
          };
          swap = {
            device = "/dev/disk/by-partlabel/disk-disk1-swap";
            crypttabExtraOpts = [ "tpm2-device=auto" ];
          };
        };
      };
      # Resume device for encrypted swap partition
      resumeDevice = "/dev/disk/by-label/swap";
    };
    disko = {
      # 8GB is the recommeneded minimum for ZFS, so we are using this for VMs to avoid `cp` oom errors.
      memSize = 18432;
      imageBuilder = {
        extraPostVM = lib.mkIf (config.ghaf.imageBuilder.compression == "zstd") ''
          ${pkgs.zstd}/bin/zstd --compress $out/*raw
          rm $out/*raw
        '';
      };
      devices = {
        disk.disk1 = {
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
              };
              swap = {
                size = "38G";
                type = "8200";
                content = {
                  type = "swap";
                  extraArgs = [ "-L swap" ]; # Label the partition
                };
              };
              zfs_root = {
                size = "30G";
                content = {
                  type = "zfs";
                  pool = "zfs_root";
                };
              };
              zfs_data = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "zfs_data";
                };
              };
            };
          };
        };

        zpool = {
          zfs_root = {
            type = "zpool";
            rootFsOptions = {
              mountpoint = "none";
              acltype = "posixacl";
              compression = "lz4";
              xattr = "sa";
            };
            # `ashift=12` optimizes alignment for 4K sector size.
            # Since this is an generic image and people might upgrade from one nvme device to another,
            # we should make sure it runs well on these devices, also in theory 512B would work with less.
            # This trades off some space overhead for overall better performance on 4k devices.
            options.ashift = "12";
            datasets = {
              "root" = {
                type = "zfs_fs";
                mountpoint = "/";
                options = {
                  mountpoint = "/";
                  quota = "30G";
                };
              };
            };
          };

          zfs_data =
            if !diskEncryption then
              {
                type = "zpool";
                rootFsOptions = {
                  mountpoint = "none";
                  acltype = "posixacl";
                  compression = "lz4";
                  xattr = "sa";
                };
                options.ashift = "12";
                datasets = {
                  "vm_storage" = {
                    type = "zfs_fs";
                    options = {
                      mountpoint = "/vm_storage";
                      quota = "30G";
                    };
                  };
                  "reserved" = {
                    type = "zfs_fs";
                    options = {
                      mountpoint = "none";
                      quota = "10G";
                    };
                  };
                  "gp_storage" = {
                    type = "zfs_fs";
                    options = {
                      mountpoint = "/gp_storage";
                      quota = "50G";
                    };
                  };
                  "recovery" = {
                    type = "zfs_fs";
                    options = {
                      mountpoint = "none";
                    };
                  };
                  "storagevm" = {
                    type = "zfs_fs";
                    options = {
                      mountpoint = "/storagevm";
                    };
                  };
                };
              }
            else
              {
                type = "zpool";
                # Datasets will be created on first boot
                datasets = { };
              };
        };
      };
    };
  };
}
