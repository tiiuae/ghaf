# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Read-only /nix/store for crosvm guests via --pmem-ext2, mounted with ext4 DAX.
# Imported by every VM base module via vm-modules; used when storeOnDisk is disabled.
{
  config,
  lib,
  pkgs,
  globalConfig,
  ...
}:
let
  storeOnDiskEnabled = globalConfig.storage.storeOnDisk.enable or false;
  isCrosvm = config.microvm.hypervisor == "crosvm";
  # Each VM only has access ot its own closure paths
  closure = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
in
{
  _file = ./store-pmem-ext2.nix;

  config = lib.mkIf (!storeOnDiskEnabled && isCrosvm) {
    microvm = {
      crosvm.extraArgs = [
        "--pmem-ext2"
        "/nix/store:paths=${closure}/store-paths:blocks_per_group=32768:inodes_per_group=8192"
      ];
      # microvm.nix defaults to an erofs store disk when no /nix/store share exists
      storeOnDisk = false;
      writableStoreOverlay = "/nix/.rw-store";
    };

    boot.initrd.availableKernelModules = [
      "virtio_pmem"
      "nd_pmem"
    ];
    # libnvdimm's encrypted_keys dependency needs cbc(aes) to init; load it explicitly
    boot.initrd.kernelModules = [
      "cbc"
      "aes"
    ];

    fileSystems = {
      "/nix/.ro-store" = {
        device = "/dev/pmem0";
        fsType = "ext4";
        options = [
          "ro"
          "dax"
        ];
        neededForBoot = true;
        noCheck = true;
      };
      # microvm.nix derives the lower dir from a /nix/store share, which no longer exists
      "/nix/store".overlay.lowerdir = lib.mkForce [ "/nix/.ro-store" ];
    };
  };
}
