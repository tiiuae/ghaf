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

    # BPMP allow-list: union of the bpmp ids the passed-through compute engines
    # declare in the live host DT (only cells whose phandle is &bpmp):
    #   gpu@17000000    clocks 304 41 236   reset 19    pd 35
    #   host1x@13e00000 clocks 46 1
    #   vic@15340000    clock 167           reset 113   pd 29
    #   nvdec@15480000  clocks 83 40 154    reset 44    pd 23
    #   nvjpg@15540000  clock 20            reset 10    pd 36
    # display@13800000 is host-side now, so the guest no longer requests these display
    # ids, but they stay in the closed allow-list (still NOT allow-all) so it need not
    # change if the guest re-acquires a display path. They are the exact ids the guest
    # display@13800000 node declares. dce@d800000 needs no ids (host owns the real DCE;
    # the guest's synthetic dce node has no clocks). The host proxy logging "clock not
    # allowed" for probed parent PLLs is the boundary working; add an id only if
    # display/GPU init actually fails on that denied id.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = {
      # compute engines (see per-device breakdown above)
      clocks = [
        1
        20
        40
        41
        46
        83
        154
        167
        236
        304
      ]
      # 13800000.display: nvdisplayhub/disp/p0/p1, dpaux, fuse, the DSI/SP/V
      # PLL tree, RG/SOR/SF paths, mipi-cal, osc, dsc, maud, aza.
      ++ [
        # Root parents of the SOR clock tree. The guest's clk_prepare_enable on sor0
        # propagates enables up to these; a denied parent fails the WHOLE chain, so
        # the SOR never turns on (no video despite a completed modeset). Host-critical
        # always-on roots: a guest enable is a BPMP refcount no-op, and the guest runs
        # clk_ignore_unused so it never mass-disables them.
        14 # TEGRA234_CLK_CLK_M
        102 # TEGRA234_CLK_PLLP_OUT0
        19
        40
        71
        72
        84
        85
        86
        87
        88
        91
        125
        126
        127
        128
        129
        130
        132
        162
        178
        179
        180
        181
        182
        183
        184
        # NOTE: the guest display RM also probes host-critical clocks during its
        # clock-tree walk (429-434=CPU DSU/SCE/RCE/DCE_CPU, 472=MCHUB, etc). Those
        # denials are CORRECT and HARMLESS (host already runs them) and must STAY
        # denied -- never add CPU/coprocessor/memory clocks here. The list above is
        # exactly the 62 clock ids the guest display@13800000 node declares.
        435
        436
        437
        438
        439
        440
        441
        442
        443
        444
        445
        446
        447
        448
        449
        450
        451
        452
        453
        454
        455
        456
        457
        458
        459
        460
        461
        462
        463
        464
        465
        466
        467
        468
        469
        470
        471
      ];
      # compute resets ++ display (nvdisplay 16, dpaux 8, dsi-core 3, mipi-cal 37)
      resets = [
        10
        19
        44
        113
      ]
      ++ [
        3
        8
        16
        37
      ];
      # compute power-domains ++ display DISP (3)
      powerDomains = [
        23
        29
        35
        36
      ]
      ++ [ 3 ];
    };

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
