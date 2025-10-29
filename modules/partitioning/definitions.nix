# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  partDef = types.submodule {
    options = {
      size = mkOption {
        type = types.str; # FIXME: validation
        description = "Partition minimal size";
      };
      mountPoint = mkOption {
        type = types.str; # FIXME: validation
        description = "Partition's filesystem mount point";
      };
      fileSystem = mkOption {
        type = types.enum [
          "ext4"
          "btrfs"
          "xfs"
          "erofs"
          "swap"
          "vfat"
        ];
        description = "File system to put on partition";
      };
    };
  };
  assertions =
    let
      cfg = config.ghaf.partitions;
    in
    [
      {
        assertion = builtins.hasAttr cfg.definition "esp";
        message = "ESP partition must be defined";
      }
      {
        assertion = builtins.hasAttr cfg.definition "swap";
        message = "Swap partition must be defined";
      }
      {
        assertion = builtins.hasAttr cfg.definition "root";
        message = "Root partition must be defined";
      }
      {
        assertion = builtins.hasAttr cfg.definition "persist";
        message = "Persist partition must be defined";
      }
    ];
in
{
  options = {
    ghaf.partitions = {
      enableABScheme = mkOption {
        type = types.bool;
        default = true;
      };
      rootFilesystemType = mkOption {
        internal = true;
        default = "ext4";
        description = ''
          Type of rootfs (A slot)
          Defaulted to "ext4" for disko, but should be overriden for erofs images
        '';
      };
      definition = mkOption {
        type = types.attrsOf partDef;
      };
    };
  };

  config.ghaf.partitions.definition = {
    inherit assertions;
    esp = {
      size = "512M";
      mountPoint = "/boot";
      fileSystem = "vfat";
    };
    swap = {
      size = "12G";
    };
    # FIXME: Need build time assertion, that resulting image fits
    root = {
      size = "64G";
      mountPoint = "/";
      fileSystem = config.ghaf.partitions.rootFilesystemType;
    };
    persist = {
      size = "1G";
      mountPoint = "/persist";
      fileSystem = "btrfs";
    };
  };
}
