# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Combined GPU, media, and display passthrough to gui-vm.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gui_vm;

  virt = config.ghaf.hardware.nvidia.virtualization;

  inherit (import ../payload { inherit lib pkgs; })
    capabilities
    mkPayload
    boardFor
    ;
  cap = capabilities.guivm;
  payload = mkPayload cap;
  board = boardFor config.ghaf.hardware.nvidia.orin.somType;

  mkOrinGpuDtb = import ../payload/dtb.nix;
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;

  guivm-dtb = mkOrinGpuDtb {
    inherit lib pkgs board;
    cap = capabilities.guivm;
    kernel = config.boot.kernelPackages.kernel;
    dtsDir = "${pkgs.nvidia-jetpack.orinVirtualizationSupport}/device-trees/gpu-vm";
  };

  withPkvm = config.ghaf.host.kernel.hardening.hypervisor.enable;

  inherit (config.lib.jetpack) preprocessDtsi;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.gui_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Pass the Tegra234 GPU, engines and display through to a single combined microvm, gui-vm, on NVIDIA Orin AGX";
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    ghaf.virtualization.microvm.guivm.enable = true;

    assertions = [
      {
        assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
        message = "gui_vm passthrough requires the closed BPMP allow-list; ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains must stay false.";
      }
    ];

    warnings = [
      "gui_vm passthrough is enabled: the host GPU is assigned to gui-vm, so the host graphics stack (COSMIC desktop), nvpmodel, and NVIDIA Docker are force-disabled. The host has no local GUI."
    ];

    # Shared closed allowlist is the BPMP security boundary.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = lib.mkIf (!withPkvm) (
      import ../payload/bpmp-allowlist.nix
    );

    services.udev.extraRules = ''
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
      SUBSYSTEM=="vfio", GROUP="kvm"
    ''
    + lib.optionalString withPkvm ''
      KERNEL=="bpmp_host", GROUP="kvm", MODE="0660"
      KERNEL=="pkvm-guest-ram", GROUP="kvm", MODE="0660"
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
      "host1x_nvhost"
      "host1x_fence"
      "nvhost_isp5"
      "nvhost_vi5"
      "nvhost_nvcsi"
      "nvhost_nvdla"
      "nvhost_pva"
      "tegra_camera"
      "tegra_se"
    ];

    systemd.services.bindGuiVm = {
      description = "Bind GPU + display devices to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@gui-vm.service" ];
      serviceConfig =
        let
          devices =
            if withPkvm then
              [
                "17000000.gpu"
                "13e00000.host1x"
                "60000000.pkvm-host1x-syncpt-dev"
              ]
            else
              payload.hostDevices;
        in
        {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStartPre = map (
            d:
            "${pkgs.bash}/bin/bash -c \"echo vfio-platform > /sys/bus/platform/devices/${d}/driver_override\""
          ) devices;
          ExecStart = map (
            d: "${pkgs.bash}/bin/bash -c \"echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind\""
          ) devices;
        };
    };

    systemd.services."microvm@gui-vm" = {
      wants = [ "bindGuiVm.service" ];
      after = [ "bindGuiVm.service" ];
      environment = lib.mkIf payload.needsDceBridge { GHAF_DCE_GUEST = "1"; };
    };

    ghaf.host.kernel.hardening.allowedPassthroughDevices = [
      "ga10b"
      "host1x"
      "pkvm_host1x_syncpt_dev"
    ];

    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile =
          if withPkvm then
            ./gpu_protected_passthrough_overlay.dts
          else
            "${pkgs.nvidia-jetpack.orinVirtualizationSupport}/device-trees/gpu-vm/gpu_passthrough_overlay.dts";
      }
    ];

    ghaf.hardware.definition.guivm.extraModules = [
      (
        if !withPkvm then
          (mkOrinGpuGuestModule {
            inherit lib;
            cap = capabilities.guivm;
            dtb = guivm-dtb;
            inherit (payload) vfioArgs;
            inherit (virt) sourcesPatch;
          })
        else
          (_: {
            imports = [ ./jetson-guest-graphics.nix ];

            config = {
              boot.kernelParams = [ "cma=256M" ];

              microvm.crosvm.extraArgs =
                let
                  gpuOverlay = preprocessDtsi { dtsFile = ./gpu-guest-overlay.dts; };
                in
                [
                  "--vendor-devices"
                  "bpmp"
                  "--device-tree-overlay"
                  "${gpuOverlay}"
                  "--ram-base"
                  "0x140000000"
                  "--file-backed-mapping"
                  "path=/dev/pkvm-guest-ram,addr=0x140000000,size=0x340000000,rw,ram=true"
                  "--vfio"
                  "/sys/bus/platform/devices/17000000.gpu/,iommu=pkvm-iommu,dt-symbol=ga10b"
                  "--vfio"
                  "/sys/bus/platform/devices/13e00000.host1x/,iommu=pkvm-iommu,dt-symbol=host1x"
                  "--vfio"
                  "/sys/bus/platform/devices/60000000.pkvm-host1x-syncpt-dev/,iommu=pkvm-iommu,dt-symbol=host1x_syncpt,guest-mmio-base=0x60000000,guest-mmio-size=0x4000000"
                ];
            };
          })
      )
    ];
  };
}
