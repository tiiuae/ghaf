# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC GPU (ga10b) and supporting engines to gpu-vm.
#
# Data:    vfio-platform hands the GPU + host1x/vic/nvdec/nvjpg + three
#          reserved-memory carveouts to the guest. Carveouts use mmio-base for
#          1:1 GPA=HPA (see ghaf-qemu-bpmp-gpu).
# Control: clocks/resets/power-domains route through the BPMP host proxy, gated
#          by the union allow-list (ids enumerated on hardware).
#
# Display (13800000.display) is NOT passed through: the host-owned DCE R5 keeps
# it and drives scanout. vfio-binding display resets it under the R5, which then
# aborts at dce_ss_set (DCE_HALTED) -- the binding alone, not guest activity.
# The guest reaches the panel only via the DCE host-proxy IPC path, never MMIO.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpu_vm;

  # Host-side virtualization config (sourcesPatch is here, not on the guest);
  # captured from host scope so guest extraModules can reference it without the
  # inner `config` shadow resolving to the guest config.
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
    # 1:1 scanout carveout: nvdisplay allocates its scanout surface here, the
    # host DCE R5 DMAs it at the same PA. Mirrors scanout_p in the overlay dts
    # and dce_scanout in tegra234-gpuvm.dts.
    {
      dev = "b0000000.scanout_p";
      base = "0xb0000000";
    }
  ];
  # GPU compute engines. Neither dce@d800000 nor display@13800000 is here:
  # host keeps the real DCE and its R5 drives display directly (vfio-binding
  # display halts the R5, DCE_HALTED at dce_ss_set). Guest reaches the panel
  # only via the DCE host-proxy IPC path.
  #
  # host1x@13e00000 is passed: the guest GPU stack (nvgpu) needs host1x
  # syncpoints. If the R5 still halts, host1x is the next candidate to keep
  # host-side (costs guest GPU compute until the guest gets a virtual host1x).
  engines = [
    "17000000.gpu"
    "13e00000.host1x_pt"
    "15340000.vic"
    "15480000.nvdec"
    "15540000.nvjpg"
  ];
  # Keyhole MMIO passthrough: single 4KB read-only EVO display-capabilities strap
  # page (0x13830000 = display+0x30000), placed in the guest at its caps offset
  # (0x66230000 = 0x66200000+0x30000) via mmio-base. Backs the guest nvdisplay
  # EvoGetCapabilities read WITHOUT handing over the display control aperture
  # (that needs rewriting display@13800000, which kills the host DCE R5). See
  # overlay fragment@9. Only this page is backed, so any OTHER display-register
  # access still aborts (exposes the guest's real MMIO footprint).
  # Second keyhole: EVO channel doorbell (PUT/GET) region -- core at
  # display+0x70000, window channels from display+0x80000 -- mapped to guest
  # 0x66270000 (0x66200000+0x70000), size 0x20000. nvkms writes PUT here to tell
  # the DCE R5 to fetch a channel's pushbuffer; unbacked, the window channel's
  # GET never advances. See overlay fragment@10. CPU-RM user doorbells; R5-safe.
  # NOTE: dpaux0 (0x155C0000) and MIPI_CAL (0x03990000) deliberately NOT keyholed
  # -- tried, proved INERT: on T234D the CPU-side RM never instantiates OBJDPAUX,
  # so no guest code touches them; EDID/AUX are RmControl -> DCE-RPC on the R5,
  # which owns the pads. Keyholing them changed nothing.
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
  allDevs = (map (r: r.dev) (reservedMem ++ dispCaps)) ++ engines;

  vfioArgs =
    (lib.concatMap (r: [
      "-device"
      "vfio-platform,host=${r.dev},mmio-base=${r.base}"
    ]) (reservedMem ++ dispCaps))
    ++ (lib.concatMap (d: [
      "-device"
      "vfio-platform,host=${d}"
    ]) engines);

  # Guest device tree -> dtb. dt-bindings come from the guest kernel's mainline
  # headers; their TEGRA234_CLK_*/RESET_*/POWER_DOMAIN_* ids equal the SoC's
  # live-DT ids, so the guest requests exactly what the host proxy allow-list
  # grants. Two NVIDIA-only headers (tegra234-irq.h, tegra234-p2u.h) are vendored
  # under ./nv-dt-bindings.
  gpuvm-dtb = pkgs.stdenv.mkDerivation {
    name = "gpuvm-dtb";
    src = ./tegra234-gpuvm.dts;
    dontUnpack = true;
    # Build-platform tools: preprocesses + compiles a device tree (arch-agnostic
    # text) at build time, so it runs on the builder -- buildPackages makes `gcc`
    # the native compiler in a cross build.
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

    # The closed BPMP host-proxy allow-list is the host-safety boundary;
    # bpmpAllowAllDomains bypasses it. Fail the build rather than ship a guest
    # that can reach every SoC clock/power domain.
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
    # declare in the live host DT (cells whose phandle is &bpmp):
    #   gpu@17000000    clocks 304 41 236   reset 19    pd 35
    #   host1x@13e00000 clocks 46 1
    #   vic@15340000    clock 167           reset 113   pd 29
    #   nvdec@15480000  clocks 83 40 154    reset 44    pd 23
    #   nvjpg@15540000  clock 20            reset 10    pd 36
    # display@13800000 is host-side now, so the guest no longer requests these
    # display ids -- left in the closed allow-list harmlessly (still NOT allow-all)
    # so it need not change if the guest re-acquires a display path. They are the
    # exact ids the guest display@13800000 node declares. dce@d800000 needs no ids
    # (host owns the real DCE; the guest's synthetic dce node has no clocks). Host
    # proxy logging "clock not allowed" for probed parent PLLs is the boundary
    # working; add an id only if display/GPU init actually fails on that denied id.
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
        # Root parents of the SOR clock tree: clk_prepare_enable on sor0
        # propagates up to these, and a denied parent fails the WHOLE chain
        # (SOR never turns on despite a completed modeset -- CLK_ENABLE cmd 7
        # denials for 14/102). These are host-critical always-on roots, so the
        # bpmp-host-proxy allow-list gates them by command: a guest enable is a
        # BPMP refcount no-op, but disable/reparent/rerate are denied
        # (clk_root_is_protected) so a compromised guest cannot take them down.
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
        # NOTE: the guest display RM also probes host-critical clocks in its
        # clock-tree walk (denials 429-434=CPU DSU/SCE/RCE/DCE_CPU, 472=MCHUB).
        # Those denials are CORRECT and HARMLESS (host already runs them) and
        # must STAY denied -- never add CPU/coprocessor/memory clocks here. The
        # list above is exactly the 62 clock ids the guest display@13800000 node
        # declares (guest 6.12 tegra234-clock.h): the complete closed display set.
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
          # DRM userspace: this nvidia-drm build has no fbdev (rejects
          # nvidia-drm.fbdev), so no fbcon triggers a modeset -- connector is
          # detected with a full mode list but nothing asks for a mode, panel
          # stays dark. Ship modetest to drive a modeset from userspace until a
          # compositor runs here.
          environment.systemPackages =
            let
              # Forces plain no-modifier GBM window surfaces; see the shim
              # source for why the modifier path EGL_BAD_ALLOCs on this guest.
              gbm-nomod-shim = pkgs.runCommandCC "gbm-nomod-shim" { } ''
                mkdir -p $out/lib
                $CC -O2 -fPIC -shared -o $out/lib/gbm-nomod-shim.so \
                  ${./sources/gbm-nomod-shim.c} -ldl
              '';
              kmscube-wrapped =
                pkgs.runCommand "kmscube-nomod"
                  {
                    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
                  }
                  ''
                    mkdir -p $out/bin
                    makeWrapper ${pkgs.kmscube}/bin/kmscube $out/bin/kmscube \
                      --set LD_PRELOAD ${gbm-nomod-shim}/lib/gbm-nomod-shim.so
                  '';
            in
            [
              pkgs.libdrm
              kmscube-wrapped
              # Graphics ABI verification (accel-rendering bring-up): eglinfo/
              # eglgears prove NVIDIA EGL + a GA10B renderer string, drm_info
              # maps render/KMS nodes.
              pkgs.mesa-demos
              pkgs.drm_info
            ];

          # NVIDIA/Jetson graphics userspace (EGL/GLES/GBM) via /run/opengl-driver,
          # mirroring jetpack-nixos modules/graphics.nix. Guest can't enable
          # hardware.nvidia-jetpack (BYO kernel), so lift just the userspace wiring.
          # l4t-3d-core ships the GL vendor libs; extras carry runtime deps
          # (nvrm/gbm/wayland/nvsci).
          hardware.graphics = {
            enable = true;
            # l4t-3d-core's bundled libnvidia-egl-gbm 1.1.0 shadowed by nixpkgs
            # egl-gbm 1.1.3: 1.1.0's EGL GBM platform heap-corrupts eglInitialize
            # under mesa 26's libgbm (surfaceless/device platforms are fine).
            # First path wins in the join; drop the l4t json so the platform
            # module isn't loaded twice.
            package = pkgs.symlinkJoin {
              name = "l4t-3d-core-egl-gbm-1.1.3";
              paths = [
                # single-device fallback: on Tegra the EGL device's DRM node
                # (tegra-drm) never path-matches the gbm fd (nvidia-drm), so
                # stock matching always fails eglInitialize on GBM.
                (pkgs.egl-gbm.overrideAttrs (o: {
                  patches = (o.patches or [ ]) ++ [
                    ./patches/userspace/egl-gbm-single-device-fallback.patch
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
                # l4t-gbm minus its bundled libnvidia-egl-gbm 1.1.0 (and its
                # platform json): the nixpkgs egl-gbm 1.1.3 in `package`
                # provides that library; keep only the nvidia-drm_gbm backend.
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

          # Guest kernel = vanilla 6.12 + jetpack OOT overlay (Bring-Your-Own-
          # Kernel), GPU passthrough patches applied to nvidia-oot-modules (base
          # OOT builds clean on 6.12.93). 0003 (display passthrough) IS applied
          # for the guest display path: it force-returns the Xen dom0/vgx
          # virtualization predicates TRUE, which the in-VM nvdisplay stack needs.
          boot.kernelPackages = lib.mkForce (
            (pkgs.linuxPackages_6_12.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
              _final: prev: {
                nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
                  patches = (o.patches or [ ]) ++ [
                    ./patches/0001-gpu-add-support-for-passthrough.patch
                    ./patches/0002-add-support-for-gpu-display-passthrough.patch
                    ./patches/0003-add-support-for-display-passthrough.patch
                    # Force NISO display surfaces (pushbuffer, notifier,
                    # semaphores) contiguous so they land in the 1:1 carveout the
                    # host DCE R5 can resolve -- else the window channel never
                    # advances ("waiting for GPU progress", NVC67E).
                    ./patches/0005-force-niso-display-surfaces-contiguous.patch
                    # Address policy for everything handed to the host DCE R5
                    # (inst-mem base, pushbuffers, ctxdma FrameAddrs): CPU
                    # physical (1:1 carveout), offset into the native display
                    # high-IOVA range (raw physicals abort the R5's UPDATE),
                    # ctxdma Limit computed after the offset. Host maps
                    # hi->carveout in the display SMMU domains and retags scanout
                    # readers' MC SIDs (dce-iso-anchor).
                    ./patches/0006-dce-addresses-cpu-phys-high-iova.patch
                    # DP++ dual-mode: a passive HDMI adapter asserts HPD but has
                    # no DP sink; trust RM DDC/LOAD detection over the DP lib's
                    # HPD-only guess so detection falls through to the TMDS
                    # partner displayId where the sink is.
                    ./patches/0008-fix-dual-mode-honor-rm-connect-state.patch
                    # Core notifier: plain WRITE, never WRITE_AWAKEN -- awaken
                    # rides the DCE async event path the guest can't receive and
                    # the R5 aborts the whole completion write. Dropping this for
                    # awaken-paced completions (retried with the ch3 relay live)
                    # stops flips completing entirely; keep plain WRITE.
                    ./patches/0009-core-notifier-plain-write-no-awaken.patch
                    # Boot hotplug: a panel connected at boot produces no HPD
                    # edge, so the host DCE never sends the hotplug event and the
                    # SOR is never assigned (dark until replug). Schedule the same
                    # deferred hotplug work once at init.
                    ./patches/0020-synthesize-boot-hotplug-long-pulse.patch
                    # Drop the host DCE R5's flip-completion event: lands ~130ms
                    # after kickoff (~8-10fps ceiling), not a usable per-flip
                    # signal under passthrough. Completion comes from 0013's
                    # vblank qualification instead.
                    ./patches/0010-dce-drop-r5-completion-event.patch
                    # Window-channel completion notifier: plain WRITE, never
                    # WRITE_AWAKEN -- same R5 abort as the core channel (0009).
                    # Native-R5 60fps completion (WRITE_AWAKEN gated on the active
                    # primary) is blocked on an intermittent window-channel
                    # BEGUN->FINISHED latch failure at 60fps (closed R5 firmware);
                    # see native-r5-experimental.
                    ./patches/0011-window-notifier-plain-write.patch
                    # Complete each committed flip 2 physical vblank callbacks
                    # after it was armed -- a scanout-latch margin, tear-free at
                    # ~30fps. The R5-latch-reliable path while native-R5 60fps
                    # stays blocked on closed R5/window-channel firmware.
                    ./patches/0013-drm-vblank-flip-completion.patch
                  ];
                  # DCE display proxy (guest side): redirect the guest's DCE IPC
                  # through the shared MMIO window, skip the R5 bootstrap (R5 is
                  # host-owned). Hook patch is against the nvidia-oot project root
                  # (no prefix) so apply it scoped to nvidia-oot/; splice the guest
                  # proxy in as its own obj-m .ko (links tegra-dce exports, so it
                  # must build inside nvidia-oot).
                  postPatch = (o.postPatch or "") + ''
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0001-dce-virt-hooks.patch}
                    # Reverse-doorbell stage 2: export the async-event injector
                    # the guest proxy uses to deliver relayed ch3 events to
                    # nvdisplay's RM_EVENT client.
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0002-dce-client-ipc-inject.patch}
                    install -D ${../../common/dce-virt-common/sources/drivers/platform/tegra/dce-guest-proxy/dce-guest-proxy.c} \
                      nvidia-oot/drivers/platform/tegra/dce/dce-guest-proxy.c
                    echo 'obj-m += dce-guest-proxy.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile
                  '';
                });
              }
            )
          );
          # nvidia-drm.modeset=1 + fbdev=1: bring up the NVIDIA KMS layer and its
          # fbcon. fbcon drawing to the panel is the modeset TRIGGER that makes
          # nvdisplay bring up display -> DCE handshake via the proxy -> scanout.
          # Without a modeset request nothing drives the display (binds but idle).
          boot.kernelParams = [
            "clk_ignore_unused"
            "pd_ignore_unused"
            "nvidia-drm.modeset=1"
            # Never auto-disable vblank interrupts. nvidia-drm disables them when
            # the last flip completes; under the DCE proxy each re-enable is a
            # synchronous EVENT_SET_NOTIFICATION RPC to the R5 (~10ms) plus a slow
            # stream restart, quantizing flips to ~122ms (~8 fps). Always-on, the
            # R5 emits completions at the 60Hz vblank cadence.
            "drm.vblankoffdelay=0"
            # NB: this nvidia-drm build REJECTS fbdev ("unknown parameter"), so no
            # fbcon and nothing auto-requests a modeset -- connector detected with
            # a full mode list but unlit until a DRM client sets a mode. Kept in
            # case a driver that supports it is used later.
            "nvidia-drm.fbdev=1"
            # NOTE: do NOT add "video=DP-1:...e" here. The trailing 'e' forces the
            # connector on (DRM_FORCE_ON) -> nvidia-drm sets forceConnected ->
            # nvDpyGetDynamicData short-circuits to "connected" for the DP displayId
            # before consulting the DP lib or RM. The AGX DP port is DP++ dual-mode
            # (0x100 SOR_DP_A and 0x200 SINGLE_TMDS_A share one DRM connector, two
            # encoders); forcing the DP encoder on stops detect there, so the TMDS
            # partner -- where a passive HDMI adapter's sink lives -- is never
            # probed, and every EDID read fails on AUX.
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
            # DCE display proxy (guest): tegra-dce binds the synthetic dce node
            # (dce-virtual-pa, no reg) in proxy mode; dce-guest-proxy binds the
            # nvidia,dce-guest-proxy node, ioremaps the shared window, installs the
            # send redirect. Neither autoloads (OOT), so load explicitly;
            # dce-guest-proxy links tegra-dce's redirect symbol, so tegra-dce first.
            "tegra-dce"
            "dce-guest-proxy"
            # Display KMS stack: gives the guest a /dev/dri KMS device + crtcs for
            # display@13800000 (bound by nv_platform). With modeset=1 + fbdev=1
            # fbcon draws to the panel -> modeset -> nvdisplay display -> DCE
            # handshake via the proxy. nvidia-drm pulls nvidia-modeset + nvidia.
            "nvidia-modeset"
            "nvidia-drm"
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
