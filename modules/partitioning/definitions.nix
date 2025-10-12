# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ...}:
let
  inherit (lib) mkOption types;
  fsDef = defaults: types.submodule {
    options = {
      size = mkOption {
        types = types.str; # FIXME: validation
        default = defaults.size;
        description = "Partition minimal size";
      };
      mountPoint = mkOption {
        types = types.str; # FIXME: validation
        default = defaults.mountPoint;
        description = "Partition's filesystem mount point";
      };
      fileSystem = mkOption {
        types = types.enum ["ext4" "btrfs" "xfs" "erofs" "swap" "vfat"];
        default = defaults.fileSystem;
        description = "File system to put on partition";
      };
    };
  };
in
{
  options = {
    ghaf.partitions.definition = {
      esp = mkOption {
        type = fsDef {
          size = "512M";
          mountPoint = "/boot";
          fileSystem = "vfat";
        };
      };
      # FIXME: Need build time assertion, that resulting image fits
      root = mkOption {
        type = fsDef {
          size = "64G";
          mountPoint = "/nix/store";
          fileSystem = "ext4"; # FIXME: ext4/erofs autoselection? "auto" type?
        };
      };
      persist = mkOption {
        type = fsDef {
          size = "1G";
          mountPoint = "/persist";
          fileSystem = "btrfs";
        };
      };
      enableABScheme = mkOption {
        type = types.bool;
        default = true;
      };
      extraPartitions = mkOption {
        type = types.listOf types.freeform;
        description = "FIXME: point for extensions, in case if we need extra partitions added";
      };
    };
  };
}
