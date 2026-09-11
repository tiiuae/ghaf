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
        name = "Additional virt guest config";
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

    microvm.hypervisor = lib.mkForce "crosvm";
    ghaf.virtualization.crosvm.features = [ "bpmp" ];
    ghaf.virtualization.microvm.protected-vm.enable = true;
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
