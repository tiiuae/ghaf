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
  gpuSuspend =
    (config.ghaf.services.power-manager.gui.enable or false)
    && (config.ghaf.services.power-manager.gui.gpuSuspend or false);
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

    boot.kernelPatches = lib.optionals gpuSuspend [
      {
        name = "kernel-pm-test-gpu-suspend";
        patch = ./patches/kernel-pm-test-gpu-suspend.patch;
      }
    ];
  };
}
