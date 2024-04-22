# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# !!! To utilize this partition scheme, the disk size must be >252G !!!
#
# This partition scheme contains three common partitions and two LVM pools.
# First LVM pool occupies 250G and second one occupies the rest of the disk space.
# Some paritions are duplicated for the future AB SWupdate implementation.
#
# First three partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP-A : (500M) Kernel and initrd
# - ESP-B : (500M)
#
# First LVM pool contains next partitions:
# - root-A : (50G) Root FS
# - root-B : (50G)
# - vm-storage-A : (30G) Possible standalone pre-built VM images are stored here
# - vm-storage-B : (30G)
# - reserved-A : (10G) Reserved partition, no use
# - reserved-B : (10G)
# - gp-storage : (50G) General purpose storage for some common insecure cases
# - recovery : (rest of the LVM pool) Recovery factory image is stored here
#
# Second LVM pool is dedicated for Storage VM completely.
_: {
  disko.memSize = 2048;
  disko.devices = {
    disk.disk1 = {
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
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
          other_1 = {
            name = "lvm_pv_1";
            size = "250G";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
          # LVM pool that is going to be passed to the Storage VM
          other_2 = {
            name = "lvm_pv_2";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "vmstore";
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root_a = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "defaults"
                "noatime"
              ];
            };
          };
          vm_storage_a = {
            size = "30G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/vmstore";
              mountOptions = [
                "defaults"
                "nofail"
                "noatime"
              ];
            };
          };
          reserved_a = {
            size = "10G";
          };
          root_b = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountOptions = [
                "defaults"
                "noatime"
              ];
            };
          };
          vm_storage_b = {
            size = "30G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountOptions = [
                "defaults"
                "nofail"
                "noatime"
              ];
            };
          };
          reserved_b = {
            size = "10G";
          };
          gp_storage = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountOptions = [
                "defaults"
                "nofail"
                "noatime"
              ];
            };
          };
          recovery = {
            size = "100%FREE";
          };
        };
      };
      vmstore = {
        # Dedicated partition for StorageVM
        type = "lvm_vg";
        lvs = {
          storagevm = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountOptions = [
                "defaults"
                "nofail"
                "noatime"
              ];
            };
          };
        };
      };
    };
  };
}
