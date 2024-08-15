# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Example to create a bios compatible gpt partition
# To use this example, you will need to specify a device i.e.
#   { disko.devices.disk1.device = "/dev/sda"; }
{ pkgs, ... }:
{
  disko.devices = {
    disk.disk1 = {
      type = "disk";
      #TODO: hardcoding the size for now until 544 is merged
      #https://github.com/nix-community/disko/pull/544
      imageSize = "15G";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };
  disko = {
    memSize = 4096;
    extraPostVM = ''
      ${pkgs.zstd}/bin/zstd --compress $out/*raw
      rm $out/*raw
    '';
  };
}
