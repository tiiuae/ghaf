# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  jetsonKernelDrv = pkgs.callPackage ./packages/linux-pkvm-jetson {
    argsOverride.defconfig = "guest_defconfig";

    structuredExtraConfig = with lib.kernel; {
      GOLDFISH = lib.kernel.yes;
      BATTERY_GOLDFISH = lib.kernel.module;
      # virtio device support
      VSOCKETS = yes;
      VSOCKETS_LOOPBACK = yes;
      VIRTIO_VSOCKETS = yes;
      VIRTIO_BALLOON = module;
      VIRTIO_FS = module;
      SCSI_VIRTIO = module;
      # FS support
      BLK_DEV_LOOP = module;
      EROFS_FS = module;
      EROFS_FS_ZIP_DEFLATE = yes;
      EROFS_FS_ZIP_ZSTD = yes;
      OVERLAY_FS = module;
      FUSE_FS = yes;
      # Realtek Wifi drivers
      RTW88 = module;
      RTW88_8822CE = module;
      RTW88_DEBUG = yes;
      RTW88_DEBUGFS = yes;
    };
  };

  jetsonKernelPackages = pkgs.linuxPackagesFor jetsonKernelDrv;
in
{
  _file = ./orin-pkvm-guest.nix;

  ghaf.virtualization.microvm.protected-vm.enable = true;
  ghaf.virtualization.crosvm.package = pkgs.callPackage packages/crosvm { };

  boot.kernelPackages =
    if config.hardware.graphics.enable then
      (jetsonKernelPackages.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
        _final: prev: {
          nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (prevAttrs: {
            patches = (prevAttrs.patches or [ ]) ++ [
              ../passthrough/gui-vm/0002-nvgpu-stub-the-GPC-disable-fuse-read-for-guest-passt.patch
            ];
          });
        }
      )
    else
      jetsonKernelPackages;

  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
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

  ghaf.virtualization.crosvm.features = [ "vendor-devices" ];
}
