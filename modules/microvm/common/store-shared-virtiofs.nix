# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared virtiofs /nix/store mount for guest VMs -- the fallback used when
# storeOnDisk is disabled (the erofs counterpart lives in store-disk-erofs.nix).
# Imported by every VM base module via vm-modules.
{
  config,
  lib,
  globalConfig,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm;
  storeOnDiskEnabled = globalConfig.storage.storeOnDisk.enable or false;
in
{
  _file = ./store-shared-virtiofs.nix;

  options.ghaf.virtualization.microvm.roStoreCache = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "always"
        "auto"
        "never"
      ]
    );
    default = "never";
    description = ''
      virtiofs cache mode for the read-only /nix/store share mounted when
      storeOnDisk is disabled. Set to null to omit the cache setting
      entirely and use the virtiofsd default.
    '';
  };

  config = lib.mkIf (!storeOnDiskEnabled) {
    microvm = {
      shares = [
        (
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
            # Nix store paths never carry POSIX ACLs, so --posix-acl only adds a
            # getxattr lookup per access with nothing to show for it.
            posixAcl = false;
          }
          // lib.optionalAttrs (cfg.roStoreCache != null) { cache = cfg.roStoreCache; }
        )
      ];
      writableStoreOverlay = "/nix/.rw-store";

      # virtiofsd threads mostly block on host I/O, so more than the core count keeps more lookups in flight.
      virtiofsd.threadPoolSize = lib.mkDefault 64;
      # Skip the file-handle exchange and use O_PATH fds directly; /nix/store is an ordinary host filesystem.
      virtiofsd.inodeFileHandles = lib.mkDefault "never";
    };
  };
}
