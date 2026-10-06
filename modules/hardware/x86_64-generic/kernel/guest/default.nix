# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let

  buildKernel = import ../kernel-config-builder.nix { inherit config pkgs lib; };
  config_baseline = ./configs/ghaf_guest_hardened_baseline-x86;
  guest_hardened_kernel = buildKernel {
    inherit config_baseline;
    host_build = false;
  };

  cfg = config.ghaf.guest.kernel.hardening;
  baseKernelPackages =
    if cfg.enable then pkgs.linuxPackagesFor guest_hardened_kernel else pkgs.linuxPackages_latest;
  needsKernelBootAlias =
    (config.microvm.hypervisor or null) == "crosvm"
    && lib.versionAtLeast baseKernelPackages.kernel.version "7.2";
  kernelPackages =
    if needsKernelBootAlias then
      baseKernelPackages.extend (
        _final: prev: {
          # Linux 7.2 installs rebuilt x86 kernels as vmlinuz while nixpkgs
          # still advertises bzImage as the kernel target. Keep that declared
          # target usable instead of overriding the bootloader globally.
          kernel = prev.kernel.overrideAttrs (oldAttrs: {
            postInstall = (oldAttrs.postInstall or "") + ''
              if [ -e "$out/vmlinuz" ] && [ ! -e "$out/${prev.kernel.target}" ]; then
                ln -s vmlinuz "$out/${prev.kernel.target}"
              fi
            '';
          });
        }
      )
    else
      baseKernelPackages;
  isCrosvm = (config.microvm.hypervisor or null) == "crosvm";
in
{
  options.ghaf.guest.kernel.hardening = {
    enable = lib.mkOption {
      description = "Enable Ghaf Guest hardening feature";
      type = lib.types.bool;
      default = false;
    };

    graphics.enable = lib.mkOption {
      description = "Enable support for Graphics in the Ghaf Guest";
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
    boot.kernelPackages = kernelPackages;

    # Keep guest kernel changes here rather than per VM: every guest gets the
    # same list, so they all share one kernel build.
    boot.kernelPatches = [
      # Inert unless pm_test selects GPU-only mode.
      {
        name = "kernel-pm-test-gpu-suspend";
        patch = ./patches/kernel-pm-test-gpu-suspend.patch;
      }
      # https://github.com/troglobit/smcroute?tab=readme-ov-file#linux-requirements
      {
        name = "multicast-routing-config";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          IP_MULTICAST = yes;
          IP_MROUTE = yes;
          IP_PIMSM_V1 = yes;
          IP_PIMSM_V2 = yes;
          IP_MROUTE_MULTIPLE_TABLES = yes;
        };
      }
    ]
    ++ lib.optionals isCrosvm [
      # Crosvm's virtual IOMMU must be available before PCI enumeration.  Loading
      # it as a module lets passthrough drivers race ahead of the IOMMU supplier;
      # the late registration then leaves those devices without an IOMMU group and
      # DMA-backed drivers cannot probe reliably.
      {
        name = "crosvm-virtio-iommu-builtin";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          VIRTIO = yes;
          VIRTIO_PCI = yes;
          VIRTIO_IOMMU = yes;
        };
      }
      {
        name = "goldfish-battery";
        patch = null;
        structuredExtraConfig = {
          GOLDFISH = lib.kernel.yes;
          BATTERY_GOLDFISH = lib.kernel.module;
        };
      }
      {
        name = "chromiumos-virtio-tpm";
        patch = ../../../../microvm/sysvms/patches/chromiumos-virtio-tpm.patch;
        structuredExtraConfig.TCG_VIRTIO_VTPM = lib.kernel.module;
      }
    ];
  };
}
