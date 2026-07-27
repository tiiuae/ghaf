# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC GPU (ga10b) + display path through to gui-vm as one
# COMBINED VM: GPU + host1x + media engines AND the display scanout/DCE path in a
# single guest (capabilities.guivm). This is the accelerated-desktop arm; it runs
# INSTEAD of the split gpu-vm + disp-vm pair, never alongside them.
#
# Data:    vfio-platform hands GPU + host1x/vic/nvdec/nvjpg + the display MMIO
#          keyholes + reserved-memory carveouts (incl. scanout) to the one guest.
# Control: clocks/resets/power-domains route through the BPMP host proxy, gated by
#          the same closed allow-list gpu-vm uses (../payload/bpmp-allowlist.nix,
#          already covers compute + display).
#
# Unlike gpu-vm, the combined guest OWNS the display: it opts into the QEMU DCE
# bridge (GHAF_DCE_GUEST=1) so it drives scanout via the DCE host-proxy IPC path.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gui_vm;

  # Host-side virt config (sourcesPatch lives here, not on the guest). Captured from
  # the host scope so the guest extraModules can reference it without the inner
  # `config` shadow picking up the guest config.
  virt = config.ghaf.hardware.nvidia.virtualization;

  # Combined capability (Task 1: payload/default.nix): gpu + host1x + media +
  # display all true. gui-vm is the "everything in one VM" arm.
  inherit (import ../payload { inherit lib pkgs; }) capabilities mkPayload;
  cap = capabilities.guivm;
  payload = mkPayload cap;

  # Shared cap-parameterized builders, same as gpu-vm. The DTS sources default to
  # ../gpu-vm relative to payload/, so gui-vm needs no path override -- the combined
  # guest DTB is the full gpu-vm DTS with nothing dropped (expDtDefines empty).
  mkOrinGpuDtb = import ../payload/dtb.nix;
  mkOrinGpuGuestModule = import ../payload/guest-module.nix;

  guivm-dtb = mkOrinGpuDtb {
    inherit lib pkgs;
    cap = capabilities.guivm;
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

    # Register the gui-vm microvm now that its extraModules are populated below.
    ghaf.virtualization.microvm.guivm.enable = true;

    # The closed BPMP host-proxy allow-list is the host-safety boundary;
    # bpmpAllowAllDomains bypasses it. Fail the build rather than ship a guest that
    # can reach every SoC clock/power domain.
    assertions = [
      {
        assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
        message = "gui_vm passthrough requires the closed BPMP allow-list; ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains must stay false.";
      }
    ];

    # gui_vm force-disables the host graphics stack below; warn so a build expecting
    # a host desktop isn't silently shipped without one.
    warnings = [
      "gui_vm passthrough is enabled: the host GPU is assigned to gui-vm, so the host graphics stack (COSMIC desktop), nvpmodel, and NVIDIA Docker are force-disabled. The host has no local GUI."
    ];

    # Closed BPMP host-proxy allow-list, shared verbatim with gpu-vm. PR2055 proved
    # this exact list covers BOTH compute AND display, so the combined VM uses it
    # unchanged. See ../payload/bpmp-allowlist.nix for the per-device id breakdown.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = import ../payload/bpmp-allowlist.nix;

    services.udev.extraRules = ''
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
      SUBSYSTEM=="vfio", GROUP="kvm"
    '';

    # Host must not touch the GPU once it is vfio'd: leaving host graphics on faults
    # the host the instant bindGuiVm hands the GPU/host1x to vfio.
    ghaf.profiles.graphics.enable = lib.mkForce false;

    # nvpmodel needs host-GPU-driver sysfs that is gone under vfio, so it fails and
    # restarts forever. (TODO: split CPU/EMC vs GPU limits.)
    services.nvpmodel.enable = lib.mkForce false;

    # NVIDIA Docker can't reach the GPU under vfio. (TODO: run GPU containers in gui-vm.)
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
      after = [ "bindGuiVm.service" ];
      # Combined VM owns display: opt into the QEMU DCE bridge (GHAF_DCE_GUEST=1,
      # ghaf-qemu-bpmp patch 0002) so gui-vm drives scanout via the DCE host-proxy.
      # needsDceBridge is true for the guivm capability, so this is always set here.
      environment = lib.mkIf payload.needsDceBridge { GHAF_DCE_GUEST = "1"; };
    };

    # Host DT overlay exposing the GPU + display nodes to passthrough. Reuse gpu-vm's
    # overlay verbatim: the `_p` VFIO wrapper nodes + reserved-memory carveouts are
    # identical for the combined VM.
    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ../gpu-vm/gpu_passthrough_overlay.dts;
      }
    ];

    # Guest configuration for the gui-vm microvm: the shared cap-parameterized module
    # (payload/guest-module.nix) carries graphics userspace, the BYO guest kernel +
    # passthrough patches, the qemu package, and the -dtb + vfio args. cap=guivm
    # gives it the combined GPU+display module set.
    ghaf.hardware.definition.guivm.extraModules = [
      (mkOrinGpuGuestModule {
        inherit lib;
        cap = capabilities.guivm;
        dtb = guivm-dtb;
        inherit (payload) vfioArgs;
        inherit (virt) sourcesPatch;
      })
    ];
  };
}
