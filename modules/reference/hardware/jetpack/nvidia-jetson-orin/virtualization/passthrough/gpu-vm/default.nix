# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC GPU (ga10b) and supporting engines to gpu-vm.
#
# Data:    vfio-platform hands GPU + host1x/vic/nvdec/nvjpg + three reserved-memory
#          carveouts to the guest. Carveouts use mmio-base for 1:1 GPA=HPA.
# Control: clocks/resets/power-domains route through the BPMP host proxy, gated by
#          the union allow-list.
#
# display@13800000 is NOT passed through: the host-owned DCE R5 owns it and drives
# scanout. vfio-binding display resets it under the R5, which aborts at dce_ss_set
# (DCE_HALTED) -- the vfio binding alone does this, even with the guest stopped.
# The guest reaches the panel only via the DCE host-proxy IPC path, never display MMIO.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpu_vm;

  # Host-side virt config (sourcesPatch lives here, not on the guest). Captured from
  # the host scope so the guest extraModules can reference it without the inner
  # `config` shadow picking up the guest config.
  virt = config.ghaf.hardware.nvidia.virtualization;

  # Explicit compute capability (Task 1: payload/default.nix), replacing the
  # former host1xExperiment enum. gpu-vm is the "compute-with-host1x" arm:
  # keeps host1x/gpu/media, drops display.
  inherit (import ../payload { inherit lib pkgs; }) capabilities mkPayload;
  cap = capabilities.gpuvm;
  payload = mkPayload cap;

  # Shared cap-parameterized builders. payload/dtb.nix builds the guest DTB from
  # gpu-vm's own DTS sources; payload/guest-module.nix returns the guest NixOS
  # module (graphics userspace, BYO kernel + passthrough patches, qemu args).
  # gui-vm (Task 8b) reuses both with cap = capabilities.guivm.
  mkOrinGpuDtb = import ../payload/dtb.nix;
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;

  # Guest device tree -> dtb. dt-bindings come from the guest kernel's mainline
  # headers; their TEGRA234_CLK_*/RESET_*/POWER_DOMAIN_* ids equal the SoC's live-DT
  # ids, so the guest requests exactly what the host proxy allow-list grants. Two
  # NVIDIA-only headers (tegra234-irq.h, tegra234-p2u.h) are vendored under ./nv-dt-bindings.
  gpuvm-dtb = mkOrinGpuDtb {
    inherit lib pkgs;
    cap = capabilities.gpuvm;
    kernel = config.boot.kernelPackages.kernel;
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.gpu_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Pass the Tegra234 GPU and engines through to gpu-vm on NVIDIA Orin AGX";
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    # Register the gpu-vm microvm now that its extraModules are populated below.
    ghaf.virtualization.microvm.gpuvm.enable = true;

    # The closed BPMP host-proxy allow-list is the host-safety boundary;
    # bpmpAllowAllDomains bypasses it. Fail the build rather than ship a guest that
    # can reach every SoC clock/power domain.
    assertions = [
      {
        assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
        message = "gpu_vm passthrough requires the closed BPMP allow-list; ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains must stay false.";
      }
    ];

    # gpu_vm force-disables the host graphics stack below; warn so a build expecting
    # a host desktop isn't silently shipped without one.
    warnings = [
      "gpu_vm passthrough is enabled: the host GPU is assigned to gpu-vm, so the host graphics stack (COSMIC desktop), nvpmodel, and NVIDIA Docker are force-disabled. The host has no local GUI."
    ];

    # Closed BPMP host-proxy allow-list. Extracted to ../payload/bpmp-allowlist.nix
    # so gui-vm (combined GPU+display) consumes the identical list -- PR2055 proved
    # this exact list already covers BOTH compute AND display. See that file for the
    # per-device id breakdown and the SOR clock-tree / host-critical-root rationale.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = import ../payload/bpmp-allowlist.nix;

    services.udev.extraRules = ''
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
      SUBSYSTEM=="vfio", GROUP="kvm"
    '';

    # Host must not touch the GPU once it is vfio'd: leaving host graphics on faults
    # the host the instant bindGpuVm hands the GPU/host1x to vfio.
    ghaf.profiles.graphics.enable = lib.mkForce false;

    # nvpmodel needs host-GPU-driver sysfs that is gone under vfio, so it fails and
    # restarts forever. (TODO: split CPU/EMC vs GPU limits.)
    services.nvpmodel.enable = lib.mkForce false;

    # NVIDIA Docker can't reach the GPU under vfio. (TODO: run GPU containers in gpu-vm.)
    ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;

    # Blacklist so vfio binds pristine devices. host1x too: the GPU + vic/nvdec/nvjpg
    # are its clients, so with the bus down the host never binds them and they hand
    # over cleanly.
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
      # Exclusive DCE ownership (opt-in): the QEMU DCE bridge is created only when
      # GHAF_DCE_GUEST=1 (ghaf-qemu-bpmp patch 0002). A display-capable GPU-VM opts
      # in; a display-less one leaves it unset -> never opens /dev/dce-host, so it
      # can't steal disp-vm's DCE events.
      environment = lib.mkIf payload.needsDceBridge { GHAF_DCE_GUEST = "1"; };
    };

    # Host DT overlay exposing the GPU nodes to passthrough.
    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ./gpu_passthrough_overlay.dts;
      }
    ];

    # Guest configuration for the gpu-vm microvm: the shared cap-parameterized
    # module (payload/guest-module.nix) carries graphics userspace, the BYO guest
    # kernel + passthrough patches, the qemu package, and the -dtb + vfio args.
    ghaf.hardware.definition.gpuvm.extraModules = [
      (mkOrinGpuGuestModule {
        inherit lib;
        cap = capabilities.gpuvm;
        dtb = gpuvm-dtb;
        inherit (payload) vfioArgs;
        inherit (virt) sourcesPatch;
      })
    ];
  };
}
