# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This partition scheme contains three common partitions and ZFS pool.
# Some partitions are duplicated for the future AB SWupdate implementation.
#
# First three partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP-A : (500M) Kernel and initrd
# - ESP-B : (500M)
#
# ZFS datasets do not necessary need to have specified size and can be
# allocated dynamically. Quotas only restrict the maximum size of
# datasets, but do not reserve the space in the pool.
# The ZFS pool contains next datasets:
# - root-A : (30G) Root FS
# - root-B : (30G)
# - vm-storage-A : (30G) Possible standalone pre-built VM images are stored here
# - vm-storage-B : (30G)
# - reserved-A : (10G) Reserved dataset, no use
# - reserved-B : (10G)
# - gp-storage : (50G) General purpose storage for some common insecure cases
# - recovery : (no quota) Recovery factory image is stored here
# - storagevm: (no quota) Dataset is meant to be used for StorageVM
{ pkgs, ... }:
{
  # TODO Keep ZFS-related parts of the configuration here for now.
  # This allows to have all config dependencies in one place and cleans
  # other targets' configs from unnecessary components.
  networking.hostId = "8425e349";
  boot = {
    initrd.availableKernelModules = [ "zfs" ];
    supportedFilesystems = [ "zfs" ];
  };
  disko = {
    # 8GB is the recommeneded minimum for ZFS, so we are using this for VMs to avoid `cp` oom errors.
    memSize = 8192;
    extraPostVM = ''
      ${pkgs.zstd}/bin/zstd --compress $out/*raw
      rm $out/*raw
    '';
    extraRootModules = [ "zfs" ];
    devices = {
      disk.disk1 = {
        type = "disk";
        imageSize = "15G";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
              priority = 1; # Needs to be first partition
            };
            esp_a = {
              name = "ESP_A";
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
            esp_b = {
              name = "ESP_B";
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [
                  "umask=0077"
                  "nofail"
                ];
              };
            };
            zfs_1 = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zfspool";
              };
            };
          };
        };
      };
      zpool = {
        zfspool = {
          type = "zpool";
          rootFsOptions = {
            mountpoint = "none";
            acltype = "posixacl";
          };
          datasets = {
            "root_a" = {
              type = "zfs_fs";
              mountpoint = "/";
              options = {
                mountpoint = "/";
                quota = "30G";
              };
            };
            "vm_storage_a" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/vm_storage";
                quota = "30G";
              };
            };
            "reserved_a" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                quota = "10G";
              };
            };
            "root_b" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                quota = "30G";
              };
            };
            "vm_storage_b" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                quota = "30G";
              };
            };
            "reserved_b" = {
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
        };
      };
    };
  };
}
