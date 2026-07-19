# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Second microvm disp-vm, DISPLAY-ONLY (no host1x/gpu/media), runs concurrently
# with gpu-vm (experiment/orin-two-vm-host1x, Step 2). Owns 3 physical devices via
# 1:1 vfio-platform mmio-base -- scanout carveout + two display keyhole MMIO
# windows -- all already declared+reserved by gpu-vm's gpu_passthrough_overlay.dts
# (`_p` dummy nodes + reserved-memory). No new host carveouts here.
#
# The companion gpu-vm runs host1xExperiment = "compute-with-host1x": keeps
# host1x/gpu/media/shim, shrinks its guest RAM bank1 to 0x80000000..0xb0000000,
# drops its scanout claim -- releasing 0xb0000000 for disp-vm. See
# ../gpu-vm/default.nix and orin-agx.nix.
#
# Guest RAM (see tegra234-dispvm.dts): general guest RAM is plain QEMU -m emulated
# RAM, NOT a 1:1 carveout (no vm_cma_p claimed), so no host-PA collision with
# gpu-vm's separate QEMU process using the same GPA range. Only the scanout region
# (0xb0000000, real 1:1 GPA=HPA) and the display MMIO keyholes are passthrough.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.disp_vm;

  # Host-side virtualization config (sourcesPatch), same pattern as gpu-vm.
  virt = config.ghaf.hardware.nvidia.virtualization;

  # disp-vm's only physical devices: scanout carveout (1:1 GPA=HPA via mmio-base)
  # + two display keyhole MMIO windows. No engines (gpu/host1x/vic/nvdec/nvjpg),
  # no vm_cma_p/vm_hs_p/vm_cma_vram_p -- those stay with gpu-vm as host1x owner.
  # scanout_p/disp_caps_pt/disp_chan_pt are declared+reserved in
  # ../gpu-vm/gpu_passthrough_overlay.dts.
  reservedMem = [
    {
      dev = "b0000000.scanout_p";
      base = "0xb0000000";
    }
    # disp-vm guest RAM, 1:1 GPA=HPA carveout (0xb8000000..0x100000000, 1.125GB).
    # QEMU -m doesn't reliably back the guest here (virt RAM base != DTB memory@),
    # so RAM comes from this carveout, like gpu-vm's vm_cma. Disjoint from all
    # gpu-vm carveouts.
    {
      dev = "b8000000.dispram_lo_p";
      base = "0xb8000000";
    }
    {
      dev = "200000000.dispram_hi_p";
      base = "0x200000000";
    }
  ];
  dispCaps = [
    {
      dev = "13830000.disp_caps_pt";
      base = "0x66230000";
    }
    {
      dev = "13870000.disp_chan_pt";
      base = "0x66270000";
    }
  ];
  allDevs = map (r: r.dev) (reservedMem ++ dispCaps);

  vfioArgs = lib.concatMap (r: [
    "-device"
    "vfio-platform,host=${r.dev},mmio-base=${r.base}"
  ]) (reservedMem ++ dispCaps);

  # Guest device tree -> dtb. Mirrors ../gpu-vm/default.nix's gpuvm-dtb; reuses
  # gpu-vm's vendored NVIDIA-only dt-bindings headers rather than duplicating.
  dispvm-dtb = pkgs.stdenv.mkDerivation {
    name = "dispvm-dtb";
    # Composition root + disp-vm-specific memory .dtsi. base/proxies/display/
    # dummies come from ../gpu-vm via the -I path below (single source of truth),
    # built with EXP_DROP_HOST1X + EXP_DROP_GPU so the shared dtsi resolve to the
    # display-only guest.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./tegra234-dispvm.dts
        ./tegra234-dispvm-memory.dtsi
      ];
    };
    nativeBuildInputs = [
      pkgs.buildPackages.dtc
      pkgs.buildPackages.gcc
    ];
    buildPhase =
      let
        kernel = config.boot.kernelPackages.kernel;
        mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
        # Shared gpu-vm component .dtsi (+ generated DCB), reused verbatim.
        gpuvmDtsi = lib.fileset.toSource {
          root = ../gpu-vm;
          fileset = lib.fileset.unions [
            ../gpu-vm/tegra234-gpuvm-base.dtsi
            ../gpu-vm/tegra234-gpuvm-proxies.dtsi
            ../gpu-vm/tegra234-gpuvm-display.dtsi
            ../gpu-vm/tegra234-gpuvm-dummies.dtsi
            ../gpu-vm/generated
          ];
        };
      in
      ''
        $CC -E -nostdinc -undef -D__DTS__ -DEXP_DROP_HOST1X -DEXP_DROP_GPU -x assembler-with-cpp \
          -I${mainInc} \
          -I${../gpu-vm/nv-dt-bindings} \
          -I${gpuvmDtsi} \
          -I. \
          tegra234-dispvm.dts > preprocessed.dts
        dtc -I dts -O dtb -o tegra234-dispvm.dtb preprocessed.dts
      '';
    installPhase = ''
      mkdir -p $out
      cp tegra234-dispvm.dtb $out/
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.disp_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Pass the Tegra234 display path through to a second microvm, disp-vm, on NVIDIA Orin AGX";
  };

  config = lib.mkIf cfg.enable {
    # Register the disp-vm microvm (extraModules populated below).
    ghaf.virtualization.microvm.dispvm.enable = true;

    # BPMP allow-list, host bpmp.enable, host graphics/nvpmodel/nvidia-docker
    # disable, host1x/gpu module blacklist, and gpu_passthrough_overlay.dts
    # registration all come from ../gpu-vm/default.nix (gpu_vm) unconditionally on
    # its cfg.enable. disp_vm is only enabled alongside gpu_vm (see orin-agx.nix),
    # so none of that is duplicated here.

    systemd.services.bindDispVm = {
      description = "Bind disp-vm's display devices to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@disp-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = map (
          d:
          "${pkgs.bash}/bin/bash -c \"echo vfio-platform > /sys/bus/platform/devices/${d}/driver_override\""
        ) allDevs;
        # Idempotent bind: skip devices already on vfio-platform (re-bind writes
        # EBUSY). Unlike a blanket "|| true", this still fails hard if a device is
        # absent (driver symlink stays non-vfio-platform).
        ExecStart = map (
          d:
          "${pkgs.bash}/bin/bash -c '"
          + "cur=$(basename \"$(readlink -f /sys/bus/platform/devices/${d}/driver 2>/dev/null)\"); "
          + "if [ \"$cur\" != vfio-platform ]; then echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind; fi'"
        ) allDevs;
      };
    };
    # Requires (not just after): after= alone never STARTS the bind service, so
    # a manual/socket start of the VM could race past unbound devices.
    systemd.services."microvm@disp-vm" = {
      after = [ "bindDispVm.service" ];
      requires = [ "bindDispVm.service" ];
      # disp-vm is the DCE display owner: opt into the QEMU DCE bridge so only it
      # opens /dev/dce-host. See GHAF_DCE_GUEST gate in ghaf-qemu-bpmp patch 0002.
      environment.GHAF_DCE_GUEST = "1";
    };

    # Guest config: the proven display-no-host1x guest (Exp B, hardware-validated)
    # -- nvidia-modeset/nvidia-drm/tegra-dce/dce-guest-proxy, the no-syncpt patch
    # (unconditional here: disp-vm is always display-only), the DCE guest-proxy
    # postPatch splice, nvidia-drm.modeset=1, hardware.graphics. Patches referenced
    # from ../gpu-vm/patches, not duplicated.
    # ponytail: kmscube/mesa-demos/drm_info debug tools and GPU-falcon l4t-firmware
    # from gpu-vm's extraModules are NOT carried here (display bring-up doesn't need
    # them). Add back if HW debugging on disp-vm needs a KMS test client.
    ghaf.hardware.definition.dispvm.extraModules = [
      (
        { config, pkgs, ... }:
        {
          # NVIDIA/Jetson graphics userspace (EGL/GLES/GBM) via /run/opengl-driver,
          # mirroring ../gpu-vm/default.nix and jetpack-nixos modules/graphics.nix.
          hardware.graphics = {
            enable = true;
            package = pkgs.symlinkJoin {
              name = "l4t-3d-core-egl-gbm-1.1.3";
              paths = [
                (pkgs.egl-gbm.overrideAttrs (o: {
                  patches = (o.patches or [ ]) ++ [
                    ../gpu-vm/patches/userspace/egl-gbm-single-device-fallback.patch
                  ];
                }))
                pkgs.nvidia-jetpack.l4t-3d-core
              ];
              postBuild = ''
                rm -f $out/share/egl/egl_external_platform.d/nvidia_gbm.json
              '';
            };
            extraPackages =
              (with pkgs.nvidia-jetpack; [
                l4t-core
                l4t-cuda
                l4t-nvsci
                l4t-wayland
              ])
              ++ [
                (pkgs.symlinkJoin {
                  name = "l4t-gbm-sans-egl-gbm";
                  paths = [ pkgs.nvidia-jetpack.l4t-gbm ];
                  postBuild = ''
                    rm -f $out/lib/libnvidia-egl-gbm.so*
                    rm -f $out/share/egl/egl_external_platform.d/nvidia_gbm.json
                  '';
                })
              ];
          };
          # libEGL_nvidia.so.0 discovers its EGL platform modules here.
          environment.etc."egl/egl_external_platform.d".source =
            "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

          # Guest kernel = vanilla 6.12 + jetpack OOT overlay (bring-your-own),
          # same display-passthrough patch set as gpu-vm's display-no-host1x mode,
          # from ../gpu-vm/patches.
          boot.kernelPackages = lib.mkForce (
            (pkgs.linuxPackages_6_12.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
              _final: prev: {
                nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
                  patches = (o.patches or [ ]) ++ [
                    ../gpu-vm/patches/0001-gpu-add-support-for-passthrough.patch
                    ../gpu-vm/patches/0002-add-support-for-gpu-display-passthrough.patch
                    ../gpu-vm/patches/0003-add-support-for-display-passthrough.patch
                    ../gpu-vm/patches/0005-force-niso-display-surfaces-contiguous.patch
                    ../gpu-vm/patches/0006-dce-addresses-cpu-phys-high-iova.patch
                    ../gpu-vm/patches/0008-fix-dual-mode-honor-rm-connect-state.patch
                    ../gpu-vm/patches/0009-core-notifier-plain-write-no-awaken.patch
                    ../gpu-vm/patches/0020-synthesize-boot-hotplug-long-pulse.patch
                    ../gpu-vm/patches/0010-dce-drop-r5-completion-event.patch
                    ../gpu-vm/patches/0011-window-notifier-plain-write.patch
                    ../gpu-vm/patches/0013-drm-vblank-flip-completion.patch
                    # disp-vm is always display-only: no-syncpt NVKMS path applies
                    # unconditionally (gpu-vm gates it on the displayOnly arm).
                    ../gpu-vm/patches/0021-nvkms-force-no-syncpt-support.patch
                  ];
                  postPatch = (o.postPatch or "") + ''
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0001-dce-virt-hooks.patch}
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0002-dce-client-ipc-inject.patch}
                    install -D ${../../common/dce-virt-common/sources/drivers/platform/tegra/dce-guest-proxy/dce-guest-proxy.c} \
                      nvidia-oot/drivers/platform/tegra/dce/dce-guest-proxy.c
                    echo 'obj-m += dce-guest-proxy.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile
                  '';
                });
              }
            )
          );

          # nvidia-drm.modeset=1 + fbdev=1: bring up NVIDIA KMS + fbcon; the modeset
          # drives the DCE handshake through the proxy to scanout. See
          # ../gpu-vm/default.nix for full rationale.
          boot.kernelParams = [
            "clk_ignore_unused"
            "pd_ignore_unused"
            "nvidia-drm.modeset=1"
            "drm.vblankoffdelay=0"
            "nvidia-drm.fbdev=1"
          ];

          boot.extraModulePackages = [ config.boot.kernelPackages.nvidia-oot-modules ];
          boot.kernelModules = [
            "nvmap"
            "tegra-dce"
            "dce-guest-proxy"
            "nvidia-modeset"
            "nvidia-drm"
          ];

          boot.kernelPatches = [
            {
              name = "tegra fixed chip id";
              patch = ../gpu-vm/patches/0004-tegra-fixed-chip-id.patch;
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
                ARM64_PMEM = yes;
              };
            }
          ];

          ghaf.virtualization.qemu.package = lib.mkForce pkgs.ghaf-qemu-bpmp-gpu;

          microvm.qemu.extraArgs = [
            "-dtb"
            "${dispvm-dtb}/tegra234-dispvm.dtb"
          ]
          ++ vfioArgs;
        }
      )
    ];
  };
}
