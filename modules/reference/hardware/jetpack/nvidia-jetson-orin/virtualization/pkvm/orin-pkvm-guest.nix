# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.guest.hardening;

  jetsonKernelDrv = pkgs.linux_6_18_jetson_pkvm.override {
    argsOverride.defconfig = "guest_defconfig";
  };

  guestExtraConfig = {
    boot.kernelPackages = pkgs.linuxPackagesFor jetsonKernelDrv;

    boot.kernelPatches = [
      {
        name = "Guest virtio device support";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          VSOCKETS = yes;
          VSOCKETS_LOOPBACK = yes;
          VIRTIO_VSOCKETS = yes;
          VIRTIO_BALLOON = module;
          VIRTIO_FS = module;
          SCSI_VIRTIO = module;
        };
      }
      {
        name = "Guest FS support";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          BLK_DEV_LOOP = module;
          EROFS_FS = module;
          EROFS_FS_ZIP_DEFLATE = yes;
          EROFS_FS_ZIP_ZSTD = yes;
          OVERLAY_FS = module;
          FUSE_FS = yes;
        };
      }
    ];

    hardware.enableAllHardware = false;
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [
      "virtiofs"
      "virtio_net"
      "virtio_pci"
      "virtio_mmio"
      "virtio_blk"
      "virtio_scsi"
      "virtio_console"
      "vsock"
    ];

    ghaf.virtualization.microvm.protected-vm.enable = true;
    ghaf.virtualization.crosvm.features = [ "bpmp" ];
  };
in
{
  _file = ./orin-pkvm-guest.nix;

  config = lib.mkIf cfg.protected.enable {
    ghaf.virtualization.vmConfig.sysvms = {
      netvm.extraModules = [
        guestExtraConfig
      ];

      adminvm.extraModules = [
        guestExtraConfig
      ];
    };

    assertions = [
      {
        assertion = cfg.protected.enable -> config.ghaf.host.kernel.hardening.hypervisor.enable;
        message = "Host kernel must have protected guest support to enable config.ghaf.guest.hardening";
      }
    ];
  };
}
