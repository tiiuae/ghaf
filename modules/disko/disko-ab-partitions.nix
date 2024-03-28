# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
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
          # LVM pool that is going to be encrypted
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
          gp_storage = {
            # general purpose storage
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
