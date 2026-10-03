# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The generic hardening in modules/common/systemd/hardened-configs/microvm.nix
# is the same for every guest, but the privileges crosvm needs depend on whether
# or not the /nix/store share is mounted with DAX
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm-host;

  vmUsesDax =
    vmEntry:
    let
      vmConfig = lib.ghaf.vm.getConfig vmEntry;
    in
    vmConfig != null
    && (
      lib.any (share: share.dax or false) (vmConfig.microvm.shares or [ ])
      || lib.elem "--pmem-ext2" (vmConfig.microvm.crosvm.extraArgs or [ ])
    );

  daxEnabled = lib.any vmUsesDax (lib.attrValues config.microvm.vms);
in
{
  _file = ./crosvm-dax.nix;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        systemd.services."microvm@".serviceConfig =
          if daxEnabled then
            {
              # CapabilityBoundingSet only raises the ceiling for a non-root unit;
              # AmbientCapabilities grants it.
              AmbientCapabilities = [
                "CAP_SYS_ADMIN"
                "CAP_SYS_CHROOT"
              ];
            }
          else
            {
              CapabilityBoundingSet = [
                "~CAP_SYS_ADMIN"
                "~CAP_SYS_CHROOT"
              ];
              RestrictNamespaces = [ "~mnt" ];
            };
      }
      (lib.mkIf daxEnabled {
        # crosvm pages the pmem-ext2 metadata out after mkfs and zswap keeps it compressed in RAM
        boot.zswap = {
          enable = true;
          maxPoolPercent = 20;
        };
        # The sysfs path units re-fire during shutdown and cancel it
        boot.kernel.sysfs.module.zswap = lib.mkForce { };
      })
    ]
  );
}
