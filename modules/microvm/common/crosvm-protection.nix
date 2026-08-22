# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.microvm;
  protection = cfg.crosvm.protection;
  isProtected = protection.mode != "unprotected";
  rawProtectionArgs = [
    "--protected-vm"
    "--protected-vm-with-firmware"
    "--protected-vm-without-firmware"
    "--swiotlb"
    "--unprotected-vm-with-firmware"
  ];
in
{
  _file = ./crosvm-protection.nix;

  options.microvm.crosvm.protection = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "unprotected"
        "protected-without-firmware"
        "protected-with-firmware"
      ];
      default = "unprotected";
      description = "Crosvm guest-memory protection mode.";
    };

    firmware = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = "Custom protected-VM firmware used by the protected-with-firmware mode.";
    };

    swiotlbSizeMiB = lib.mkOption {
      type = with lib.types; nullOr ints.positive;
      default = null;
      description = ''
        Size in MiB of the protected guest's static SWIOTLB restricted DMA
        pool. Protected guests use 64 MiB when this is null. Virtio devices
        advertise VIRTIO_F_ACCESS_PLATFORM and use this explicitly shared
        pool instead of exposing private guest memory to host backends.
      '';
    };

    allowDeviceAssignment = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow devices using Crosvm's pKVM IOMMU path in this protected guest.
        This is an experimental target-specific opt-in and requires a host
        pKVM backend that implements protected device assignment and reset.
      '';
    };
  };

  config.assertions = lib.optionals cfg.guest.enable [
    {
      assertion = lib.all (arg: !builtins.elem arg cfg.crosvm.extraArgs) rawProtectionArgs;
      message = "Use `microvm.crosvm.protection` instead of raw Crosvm protection arguments.";
    }
    {
      assertion = !isProtected || cfg.hypervisor == "crosvm";
      message = "Protected MicroVMs require the crosvm hypervisor.";
    }
    {
      assertion = !isProtected || pkgs.stdenv.hostPlatform.isAarch64;
      message = "Crosvm protected MicroVMs are currently supported only on AArch64.";
    }
    {
      assertion = protection.mode == "protected-with-firmware" || protection.firmware == null;
      message = "`microvm.crosvm.protection.firmware` requires protected-with-firmware mode.";
    }
    {
      assertion = protection.mode != "protected-with-firmware" || protection.firmware != null;
      message = "protected-with-firmware mode requires `microvm.crosvm.protection.firmware`.";
    }
    {
      assertion = isProtected || protection.swiotlbSizeMiB == null;
      message = "`microvm.crosvm.protection.swiotlbSizeMiB` requires a protected mode.";
    }
    {
      assertion = !isProtected || !cfg.balloon;
      message = "Crosvm protected MicroVMs do not support ballooning in Ghaf yet.";
    }
    {
      assertion = !isProtected || cfg.shares == [ ];
      message = "Crosvm protected MicroVMs cannot use host shared-directory backends.";
    }
    {
      assertion = !protection.allowDeviceAssignment || isProtected;
      message = "Protected device assignment requires a protected Crosvm mode.";
    }
    {
      assertion =
        !protection.allowDeviceAssignment
        || lib.all ({ crosvm, ... }: crosvm.iommu == "pkvm-iommu") cfg.devices;
      message = "Protected device assignment requires `iommu = \"pkvm-iommu\"` for every assigned device.";
    }
    {
      assertion =
        !protection.allowDeviceAssignment || lib.all ({ bus, ... }: bus == "platform") cfg.devices;
      message = "Protected device assignment currently supports platform devices only; PCI requires a pKVM reset and ownership backend.";
    }
    {
      assertion = !isProtected || cfg.devices == [ ] || protection.allowDeviceAssignment;
      message = "Crosvm protected MicroVM device assignment requires an explicit backend opt-in.";
    }
    {
      assertion = !isProtected || !cfg.graphics.enable;
      message = "Crosvm protected MicroVMs cannot use the host vhost-user graphics backend.";
    }
  ];
}
