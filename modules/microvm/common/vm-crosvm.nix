# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.crosvm;

  isCrosvm = config.microvm.hypervisor == "crosvm";

  crosvmPackage = cfg.package.overrideAttrs (oldAttrs: {
    cargoBuildFeatures = oldAttrs.cargoBuildFeatures ++ cfg.features;
    patches = (oldAttrs.patches or [ ]) ++ cfg.patches;
  });

  # `--log-level` is a global crosvm option, so argh only accepts it before the
  # `run` subcommand.  microvm.nix appends `crosvm.extraArgs` after `run`, and
  # crosvm ignores RUST_LOG, which leaves wrapping the binary as the only way to
  # set the log level of the `microvm@<vm>.service` units.
  crosvmWithLogLevel = pkgs.symlinkJoin {
    name = "${crosvmPackage.name}-log-level";
    paths = [ crosvmPackage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/crosvm --add-flags "--log-level=${cfg.logLevel}"
    '';
    meta = (crosvmPackage.meta or { }) // {
      mainProgram = "crosvm";
    };
  };
in
{
  _file = ./vm-crosvm.nix;

  # Crosvm's serial console makes systemd's per-unit shutdown status output
  # expensive. The messages remain available in the guest journal; suppressing
  # only their console rendering avoids adding seconds to every guest shutdown.
  systemd.settings.Manager.ShowStatus = lib.mkIf isCrosvm false;

  boot.kernelPatches =
    lib.optionals (isCrosvm && pkgs.stdenv.hostPlatform.isx86_64) [
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
    ]
    ++ lib.optionals cfg.gdb.enable [
      {
        name = "Kernel debug symbols";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          DEBUG_INFO = yes;
          DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = yes;
        };
      }
    ];

  microvm.crosvm.package = if cfg.logLevel == null then crosvmPackage else crosvmWithLogLevel;

  microvm.crosvm.extraArgs =
    # SMT is not available on NVIDIA Jetson Orin or generally on ARM64 platforms.
    # This causes crosvm to output unnecessary errors:
    #   ERROR crosvm::crosvm::sys::linux::vcpu] Failed to enable core scheduling: No such device (os error 19)
    lib.optionals pkgs.stdenv.hostPlatform.isAarch64 [
      "--core-scheduling"
      "false"
    ]
    ++ lib.optionals cfg.gdb.enable [
      "--gdb"
      "${lib.toString cfg.gdb.port}"
    ];

  microvm.vcpu = lib.mkIf cfg.gdb.enable 1;
}
