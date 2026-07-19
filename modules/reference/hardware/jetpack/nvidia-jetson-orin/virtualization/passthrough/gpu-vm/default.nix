# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC GPU (ga10b) and supporting engines to gpu-vm.
#
# Data:    vfio-platform hands the GPU + host1x/vic/nvdec/nvjpg + three
#          reserved-memory carveouts to the guest. The carveouts use mmio-base
#          for 1:1 GPA=HPA (large regions; see ghaf-qemu-bpmp-gpu).
# Control: clocks/resets/power-domains route through the BPMP host proxy, gated
#          by the union allow-list (ids enumerated on hardware).
#
# Display is out of scope: this is a compute-only passthrough. The
# display/dce engines are not passed through and stay with the host.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpu_vm;
  # Host scope, captured so the guest extraModules below see it past the inner
  # `config` shadow (sourcesPatch is host-side).
  virt = config.ghaf.hardware.nvidia.virtualization;

  # Reserved-memory carveouts take an explicit mmio-base for 1:1 GPA=HPA;
  # engines use the default mapping.
  reservedMem = [
    {
      dev = "60000000.vm_hs_p";
      base = "0x60000000";
    }
    {
      dev = "80000000.vm_cma_p";
      base = "0x80000000";
    }
    {
      dev = "100000000.vm_cma_vram_p";
      base = "0x100000000";
    }
  ];
  # Compute engines only. display@13800000/dce@d800000 stay with the host:
  # compute-only, and pulling display out from under the live host stack panics
  # the host at boot (OP-TEE display TA fault).
  engines = [
    "17000000.gpu"
    "13e00000.host1x_pt"
    "15340000.vic"
    "15480000.nvdec"
    "15540000.nvjpg"
  ];
  allDevs = (map (r: r.dev) reservedMem) ++ engines;

  vfioArgs =
    (lib.concatMap (r: [
      "-device"
      "vfio-platform,host=${r.dev},mmio-base=${r.base}"
    ]) reservedMem)
    ++ (lib.concatMap (d: [
      "-device"
      "vfio-platform,host=${d}"
    ]) engines);

  # Guest device tree -> dtb. dt-bindings come from the guest kernel's mainline
  # headers; their TEGRA234_CLK_*/RESET_*/POWER_DOMAIN_* ids were verified equal
  # to the SoC's live-DT ids, so the guest requests exactly what the host proxy
  # allow-list grants. Two NVIDIA-only headers (tegra234-irq.h, tegra234-p2u.h)
  # are vendored under ./nv-dt-bindings.
  gpuvm-dtb = pkgs.stdenv.mkDerivation {
    name = "gpuvm-dtb";
    src = ./tegra234-gpuvm.dts;
    dontUnpack = true;
    # Build-platform tools: this preprocesses + compiles a device tree at build
    # time (arch-agnostic text), so it must run on the builder, not the aarch64
    # target -- use buildPackages so `gcc` is the native compiler in a cross build.
    nativeBuildInputs = [
      pkgs.buildPackages.dtc
      pkgs.buildPackages.gcc
    ];
    buildPhase =
      let
        kernel = config.boot.kernelPackages.kernel;
        mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
      in
      ''
        cp $src tegra234-gpuvm.dts
        # $CC = stdenv's compiler (triple-prefixed under cross); -E only
        # preprocesses, so the target triple is irrelevant to the text output.
        $CC -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
          -I${mainInc} \
          -I${./nv-dt-bindings} \
          tegra234-gpuvm.dts > preprocessed.dts
        dtc -I dts -O dtb -o tegra234-gpuvm.dtb preprocessed.dts
      '';
    installPhase = ''
      mkdir -p $out
      cp tegra234-gpuvm.dtb $out/
    '';
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

    # The closed BPMP host-proxy allow-list is the host-safety boundary for this
    # passthrough; bpmpAllowAllDomains would bypass it. Fail the build rather than
    # ship a guest that can reach every SoC clock/power domain.
    assertions = [
      {
        assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
        message = "gpu_vm passthrough requires the closed BPMP allow-list; ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains must stay false.";
      }
    ];

    # gpu_vm force-disables the host graphics stack below (no per-device opt-out);
    # warn so a build expecting a host desktop is not silently shipped without one.
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
    # display/dce excluded (compute-only). "clock not allowed" logs for probed
    # parent clocks are the boundary working; add a denied id here only if init
    # actually fails on it.
    #
    # Shared BPMP trust domain: the host proxy enforces one allow-list (union
    # across all passthroughs, incl. net-vm's MGBE0) and gates by resource id
    # only, not by issuing guest. gpu-vm and net-vm share /dev/bpmp-host, so a
    # compromised one can MRQ_RESET the other's ids -- they are one trust domain.
    # The host stays protected (list scoped, bpmpAllowAllDomains off, asserted
    # above). A per-VM proxy would remove the residual guest<->guest reach.
    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = {
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
      ];
      resets = [
        10
        19
        44
        113
      ];
      powerDomains = [
        23
        29
        35
        36
      ];
    };

    services.udev.extraRules = ''
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
      SUBSYSTEM=="vfio", GROUP="kvm"
    '';

    # Host must not touch the GPU once it is vfio'd: leaving host graphics on
    # faults the host the instant bindGpuVm hands the GPU/host1x to vfio.
    ghaf.profiles.graphics.enable = lib.mkForce false;

    # nvpmodel needs host-GPU-driver sysfs that is gone under vfio, so its
    # service fails and restarts forever. (TODO: split CPU/EMC vs GPU limits.)
    services.nvpmodel.enable = lib.mkForce false;

    # NVIDIA Docker can't reach the GPU under vfio. (TODO: run GPU containers
    # inside gpu-vm instead.)
    ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;

    # Blacklist so vfio binds pristine devices (as MGBE0 does). host1x too: the
    # GPU + vic/nvdec/nvjpg are its clients, so with the bus down the host never
    # binds them and they hand over cleanly.
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
        ) allDevs;
        ExecStart = map (
          d: "${pkgs.bash}/bin/bash -c \"echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind\""
        ) allDevs;
      };
    };
    systemd.services."microvm@gpu-vm".after = [ "bindGpuVm.service" ];

    # Host DT overlay exposing the GPU nodes to passthrough.
    hardware.deviceTree.overlays = [
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ./gpu_passthrough_overlay.dts;
      }
    ];

    # Guest configuration for the gpu-vm microvm.
    ghaf.hardware.definition.gpuvm.extraModules = [
      (
        { config, pkgs, ... }:
        {
          # Guest kernel = vanilla 6.12 + jetpack OOT overlay (bring-your-own),
          # GPU passthrough patches on nvidia-oot-modules. 0003 (display) is
          # intentionally NOT applied: out of scope here, and it forces the
          # Xen dom0/vgx predicates TRUE -- dead, risky in a compute build.
          boot.kernelPackages = lib.mkForce (
            (pkgs.linuxPackages_6_12.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
              _final: prev: {
                nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
                  patches = (o.patches or [ ]) ++ [
                    ./patches/0001-gpu-add-support-for-passthrough.patch
                    ./patches/0002-add-support-for-gpu-display-passthrough.patch
                  ];
                });
              }
            )
          );
          # Safety params: without them the guest can gate off clocks/domains the
          # host still uses. Asserted present below.
          boot.kernelParams = [
            "clk_ignore_unused"
            "pd_ignore_unused"
          ];

          assertions = [
            {
              assertion =
                (lib.elem "clk_ignore_unused" config.boot.kernelParams)
                && (lib.elem "pd_ignore_unused" config.boot.kernelParams);
              message = "gpu-vm guest must boot with both clk_ignore_unused and pd_ignore_unused, or it can power off clocks/domains the host still uses.";
            }
          ];

          # OOT GPU drivers don't autoload from a DT match (unlike in-tree
          # dwmac), so load them explicitly -- else nothing binds gpu@17000000,
          # no /dev/nvgpu|nvmap|nvhost-*, and CUDA's NvRmMemMgr init fails.
          boot.extraModulePackages = [ config.boot.kernelPackages.nvidia-oot-modules ];
          boot.kernelModules = [
            "nvmap"
            "host1x"
            "nvhost"
            "nvgpu"
          ];

          # gk20a loads falcon microcode from /lib/firmware at probe; without it
          # the probe times out (-110). Ship the L4T GPU firmware.
          hardware.firmware = [ pkgs.nvidia-jetpack.l4t-firmware ];

          boot.kernelPatches = [
            {
              name = "tegra fixed chip id";
              patch = ./patches/0004-tegra-fixed-chip-id.patch;
            }
            {
              name = "bpmp-virt proxy drivers";
              patch = virt.sourcesPatch;
            }
            {
              name = "bpmp-virt core hooks";
              patch = ../../common/bpmp-virt-common/patches/0001-bpmp-virt-hooks-6.12.patch;
            }
            {
              name = "bpmp guest proxy kernel configuration";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                ARCH_TEGRA = yes;
                ARCH_TEGRA_234_SOC = yes;
                TEGRA_HSP_MBOX = yes;
                TEGRA_IVC = yes;
                TEGRA_BPMP = yes;
                TEGRA_BPMP_GUEST_PROXY = yes;
                TEGRA_BPMP_HOST_PROXY = no;
                CLK_TEGRA_BPMP = yes;
                RESET_TEGRA_BPMP = yes;
                PM_GENERIC_DOMAINS = yes;
                # Required by NVIDIA Bring-Your-Own-Kernel for the OOT modules.
                ARM64_PMEM = yes;
              };
            }
          ];

          ghaf.virtualization.qemu.package = lib.mkForce pkgs.ghaf-qemu-bpmp-gpu;

          microvm.qemu.extraArgs = [
            "-dtb"
            "${gpuvm-dtb}/tegra234-gpuvm.dtb"
          ]
          ++ vfioArgs;
        }
      )
    ];
  };
}
