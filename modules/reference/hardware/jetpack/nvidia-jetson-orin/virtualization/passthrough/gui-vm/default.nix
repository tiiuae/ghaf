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
  configuredGuiVmVmm = config.ghaf.virtualization.vmConfig.sysvms.guivm.vmm or null;
  guiVmVmm =
    if configuredGuiVmVmm != null then
      configuredGuiVmVmm
    else
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm;
  isCrosvm = guiVmVmm == "crosvm";

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
  mkOrinGpuCrosvmOverlay = import ../payload/crosvm-overlay.nix;
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;

  guivm-dtb = mkOrinGpuDtb {
    inherit lib pkgs board;
    cap = capabilities.guivm;
    kernel = config.boot.kernelPackages.kernel;
  };
  guivm-crosvm-overlay = mkOrinGpuCrosvmOverlay {
    inherit lib pkgs board;
    kernel = config.boot.kernelPackages.kernel;
  };
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

    systemd.services.bindGuiVm = {
      description = "Bind GPU + display devices to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@gui-vm.service" ];
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
    systemd.services."microvm@gui-vm" = {
      requires = [ "bindGuiVm.service" ];
      after = [ "bindGuiVm.service" ];
      environment = lib.mkIf (!isCrosvm && payload.needsDceBridge) { GHAF_DCE_GUEST = "1"; };
      serviceConfig.ExecStartPre = lib.optionals isCrosvm [
        "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -r /dev/bpmp-host && ${pkgs.coreutils}/bin/test -w /dev/bpmp-host'"
        "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -r /dev/dce-host && ${pkgs.coreutils}/bin/test -w /dev/dce-host'"
      ];
    };

    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ../gpu-vm/gpu_passthrough_overlay.dts;
      }
    ];

    ghaf.hardware.definition.guivm.extraModules = [
      (mkOrinGpuGuestModule {
        inherit lib;
        cap = capabilities.guivm;
        dtb = guivm-dtb;
        crosvmOverlay = guivm-crosvm-overlay;
        inherit (payload) vfioArgs;
        inherit (virt) sourcesPatch;
      })
    ];
  };
}
