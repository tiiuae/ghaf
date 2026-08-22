# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Compute GPU, host1x, and media passthrough to gpu-vm.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpu_vm;
  configuredGpuVmVmm = config.ghaf.virtualization.vmConfig.sysvms.gpuvm.vmm or null;
  gpuVmVmm =
    if configuredGpuVmVmm != null then
      configuredGpuVmVmm
    else
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm;
  isCrosvm = gpuVmVmm == "crosvm";

  virt = config.ghaf.hardware.nvidia.virtualization;

  inherit (import ../payload { inherit lib pkgs; })
    capabilities
    mkPayload
    boardFor
    ;
  cap = capabilities.gpuvm;
  payload = mkPayload cap;
  board = boardFor config.ghaf.hardware.nvidia.orin.somType;

  mkOrinGpuDtb = import ../payload/dtb.nix;
  mkOrinGpuCrosvmOverlay = import ../payload/crosvm-overlay.nix;
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;

  gpuvm-dtb = mkOrinGpuDtb {
    inherit lib pkgs board;
    cap = capabilities.gpuvm;
    kernel = config.boot.kernelPackages.kernel;
  };
  gpuvm-crosvm-overlay = mkOrinGpuCrosvmOverlay {
    inherit
      lib
      pkgs
      board
      cap
      ;
    kernel = config.boot.kernelPackages.kernel;
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.gpu_vm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pass the Tegra234 GPU and engines through to gpu-vm on NVIDIA Orin AGX or NX";
    };

    containerRuntime = {
      enable = lib.mkEnableOption "Docker with NVIDIA CDI devices in gpu-vm";
      addGhafUserToDockerGroup = lib.mkEnableOption ''
        root-equivalent Docker access for the ghaf user in gpu-vm
      '';
    };

    partitionManager = {
      enable = lib.mkEnableOption "the cooperative CUDA Green Context job manager in gpu-vm; a downstream configuration must also supply trusted workload plugins";

      plugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Trusted Nix-built workload plugins loaded by gpu-partition-manager.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    ghaf.virtualization.microvm.gpuvm.enable = true;

    assertions = [
      {
        assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
        message = "gpu_vm passthrough requires the closed BPMP allow-list; ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains must stay false.";
      }
    ];

    warnings = [
      "gpu_vm passthrough is enabled: the host GPU is assigned to gpu-vm, so the host graphics stack (COSMIC desktop), nvpmodel, and NVIDIA Docker are force-disabled. The host has no local GUI."
    ];

    # Shared closed allowlist is the BPMP security boundary.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = import ../payload/bpmp-allowlist.nix;

    services.udev.extraRules = ''
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
      SUBSYSTEM=="vfio", GROUP="kvm"
    '';

    ghaf.profiles.graphics.enable = lib.mkForce false;

    services.nvpmodel.enable = lib.mkForce false;

    ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;

    # Bind the complete host1x hierarchy directly to VFIO.
    boot.blacklistedKernelModules = [
      "nvgpu"
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
      "tegra_drm"
      "host1x"
    ];

    systemd.services.bindGpuVm = {
      description = "Bind GPU devices to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@gpu-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = map (
          d:
          "${pkgs.bash}/bin/bash -c \"echo vfio-platform > /sys/bus/platform/devices/${d}/driver_override\""
        ) payload.hostDevices;
        ExecStart = map (
          d: "${pkgs.bash}/bin/bash -c \"echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind\""
        ) payload.hostDevices;
      };
    };
    systemd.services."microvm@gpu-vm" = {
      after = [ "bindGpuVm.service" ];
      serviceConfig.ExecStartPre = lib.optionals isCrosvm [
        "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -r /dev/bpmp-host && ${pkgs.coreutils}/bin/test -w /dev/bpmp-host'"
      ];
    };

    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ./gpu_passthrough_overlay.dts;
      }
    ];
    # The split topology needs the fixed 1:1 RAM banks used by disp-vm.
    hardware.deviceTree.dtboBuildExtraPreprocessorFlags = [ "-DGHAF_INCLUDE_DISPVM_RAM" ];

    ghaf.hardware.definition.gpuvm.extraModules = [
      (mkOrinGpuGuestModule {
        inherit lib;
        cap = capabilities.gpuvm;
        dtb = gpuvm-dtb;
        crosvmOverlay = gpuvm-crosvm-overlay;
        inherit (payload) vfioArgs;
        inherit (virt) sourcesPatch;
      })
      {
        ghaf.virtualization.gpuPartitionManager = {
          inherit (cfg.partitionManager) enable plugins;
        };
        ghaf.virtualization.gpuContainerRuntime = {
          inherit (cfg.containerRuntime) enable addGhafUserToDockerGroup;
        };
      }
    ];
  };
}
