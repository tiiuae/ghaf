# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared erofs storeOnDisk configuration for guest VMs. Imported by every VM
# base module via vm-modules; only takes effect when storeOnDisk is enabled
# globally (ghaf.virtualization.microvm.storeOnDisk.enable on the host).
{
  lib,
  globalConfig,
  ...
}:
let
  cfg = globalConfig.storage.storeOnDisk;
  compLevelSuffix = lib.optionalString (
    cfg.compression.level != null
  ) ",${toString cfg.compression.level}";
in
{
  _file = ./store-disk-erofs.nix;

  config = lib.mkIf (cfg.enable or false) {
    microvm = {
      storeOnDisk = true;
      storeDiskType = "erofs";
      # Defaults: -zlz4hc (all kernels), -Eztailpacking (5.16+), -Efragments (6.1+)
      # -zzstd requires Linux 6.15+ due to -E48bit (extended addressing, needed for zstd)
      # Setting storeDiskErofsFlags overrides the entire list; include defaults explicitly if needed.
      storeDiskErofsFlags = [
        "-Eztailpacking"
        "-Efragments"
        # no need to hammer all available cores
        "--workers=$(( (NIX_BUILD_CORES < 1 || NIX_BUILD_CORES > 4) ? 4 : NIX_BUILD_CORES ))"
      ]
      ++ {
        lz4hc = [ "-zlz4hc${compLevelSuffix}" ];
        zstd = [
          "-zzstd${compLevelSuffix}"
          "-E48bit"
        ];
      }
      .${cfg.compression.algorithm};
    };
  };
}
