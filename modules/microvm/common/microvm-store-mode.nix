# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global configuration for MicroVM /nix/store mode
{
  lib,
  ...
}:
{
  _file = ./microvm-store-mode.nix;
  options.ghaf.virtualization.microvm.storeOnDisk = {
    enable = lib.mkEnableOption "storeOnDisk (erofs compressed image) for all MicroVMs";
    compression = {
      algorithm = lib.mkOption {
        type = lib.types.enum [
          "lz4hc"
          "zstd"
        ];
        description = ''
          Compression algorithm used for the erofs boot disk file system.

          zstd is recommended for kernels >= 6.15 (better compression & decompression speed).
          Requires 'CONFIG_EROFS_FS_ZIP_ZSTD=y' to be set for the guest kernel config.
        '';
        default = "zstd";
      };
      level = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          The compression level to use.
          If set to `null` will use the default for each algorithm.

          1-20 for zstd (default: 3)
          1-12 for lz4hc (default: 1)
        '';
        example = 3;
      };
    };
  };
}
