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

  # Host1x-ownership experiment (experiment/orin-two-vm-host1x). Both no-host1x
  # directions drop physical host1x + 64MiB syncpoint shim + media (one unit).
  # compute-no-host1x also drops display/DCE; display-no-host1x also drops
  # GA10B/nvgpu and forces NVKMS no-syncpt mode.
  exp = cfg.host1xExperiment;
  computeNoHost1x = exp == "compute-no-host1x";
  computeWithHost1x = exp == "compute-with-host1x";
  displayOnly = exp == "display-no-host1x";
  # host1x + 64MiB shim + media move as one unit; dropped only where host1x is
  # removed (the two no-host1x experiments), kept for off and compute-with-host1x.
  dropHost1x = computeNoHost1x || displayOnly;
  # display/DCE/scanout/keyholes dropped for both compute VMs (neither drives display).
  dropDisplay = computeNoHost1x || computeWithHost1x;

  # cpp -D flags that strip/resize guest DT nodes for the host1x experiment.
  expDtDefines =
    lib.optionalString dropHost1x "-DEXP_DROP_HOST1X "
    + lib.optionalString dropDisplay "-DEXP_DROP_DISPLAY "
    + lib.optionalString displayOnly "-DEXP_DROP_GPU "
    # Shrink memory@ bank1 to 0x80000000..0xb0000000 so it no longer needs the
    # scanout carveout, releasing 0xb0000000 for the GUI VM.
    + lib.optionalString computeWithHost1x "-DEXP_SHRINK_BANK1 ";

  # Devices passed to gpu-vm. Reserved-memory carveouts take an explicit
  # mmio-base for 1:1 GPA=HPA; engines use the default mapping.
  reservedMem =
    # 64MiB syncpoint shim: moves with physical host1x -- dropped in both experiments.
    lib.optional (!dropHost1x) {
      dev = "60000000.vm_hs_p";
      base = "0x60000000";
    }
    ++ [
      {
        dev = "80000000.vm_cma_p";
        base = "0x80000000";
      }
    ]
    # GPU VRAM carveout (4GiB @ 0x100000000). LOAD-BEARING for the guest RAM map:
    # the guest memory node's bank2 (0x100000000..0x200000000) is backed 1:1 ONLY
    # by this carveout. Dropping it leaves bank2 unbacked -> guest panics in early
    # mem init before console. Keep it in every mode; a display VM never uses it as
    # VRAM, it just backs the RAM bank. Proper fix (slim guest memory map) is a follow-up.
    ++ [
      {
        dev = "100000000.vm_cma_vram_p";
        base = "0x100000000";
      }
    ]
    # 1:1 scanout carveout (128MiB @ 0xb0000000). Beyond the scanout surface,
    # LOAD-BEARING for the guest RAM map: guest memory bank1 (0x80000000..0xb8000000)
    # has its top 128MiB tail (0xb0000000..0xb8000000) backed 1:1 ONLY by this
    # carveout. Dropping it leaves the tail unbacked, so swiotlb_init memsets into a
    # hole and the guest panics at start_kernel before console. Keep it in every mode;
    # the compute VM never touches it as display. Proper fix (slim guest memory map)
    # is a follow-up.
    #
    # compute-with-host1x is that follow-up: EXP_SHRINK_BANK1 ends guest bank1 at
    # 0xb0000000 so it no longer spans this carveout -- drops scanout here AND
    # releases 0xb0000000 for the concurrent GUI VM.
    ++ lib.optional (!computeWithHost1x) {
      dev = "b0000000.scanout_p";
      base = "0xb0000000";
    };
  # GPU compute engines. Neither dce@d800000 nor display@13800000 is here: the host
  # keeps the real DCE and its R5 drives display directly (see header).
  #
  # host1x@13e00000 is passed in off/default because the guest GPU stack (nvgpu)
  # needs host1x syncpoints. It (+ shim + media) is dropped in both experiments
  # (!dropHost1x). Next candidate to keep host-side if the R5 still halts -- would
  # cost guest GPU compute until the guest gets a virtual host1x.
  engines =
    # GA10B is dropped in the display-only VM.
    lib.optional (!displayOnly) "17000000.gpu"
    # host1x + media move together, dropped in both experiments.
    ++ lib.optionals (!dropHost1x) [
      "13e00000.host1x_pt"
      "15340000.vic"
      "15480000.nvdec"
      "15540000.nvjpg"
    ];
  # Keyhole MMIO passthrough. Keyhole 1: the single 4KB read-only EVO
  # display-capabilities strap page (0x13830000), placed in the guest at caps offset
  # 0x66230000. Backs the guest nvdisplay EvoGetCapabilities read WITHOUT handing over
  # the display control aperture (rewriting display@13800000 kills the host DCE R5).
  # See gpu_passthrough_overlay.dts fragment@9. The guest node declares the full
  # aperture but only this page is backed, so any other display-register access aborts.
  # Keyhole 2: the EVO channel doorbell (PUT/GET) region -- core at display+0x70000,
  # window channels from display+0x80000 -- at guest 0x66270000, size 0x20000. The
  # guest nvkms writes PUT here to tell the DCE R5 to fetch a channel's pushbuffer;
  # without it the window channel's GET pointer never advances. See fragment@10.
  # CPU-RM-facing user doorbells (guest is the CPU RM); R5-safe.
  # NOTE: dpaux0 (0x155C0000) and MIPI_CAL (0x03990000) deliberately NOT keyholed --
  # INERT: on T234D the CPU-side RM never instantiates OBJDPAUX, so no guest code
  # touches them; EDID/AUX are RmControl -> DCE-RPC serviced by the R5 that owns the pads.
  # Entire list dropped in compute-only (keyholes meaningless without display stack).
  dispCaps = lib.optionals (!dropDisplay) [
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
  # headers; their TEGRA234_CLK_*/RESET_*/POWER_DOMAIN_* ids equal the SoC's live-DT
  # ids, so the guest requests exactly what the host proxy allow-list grants. Two
  # NVIDIA-only headers (tegra234-irq.h, tegra234-p2u.h) are vendored under ./nv-dt-bindings.
  gpuvm-dtb = pkgs.stdenv.mkDerivation {
    name = "gpuvm-dtb";
    # Composition root + component .dtsi fragments (see the include list in
    # tegra234-gpuvm.dts); generated/ holds the pinned stock-derived DCB.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./tegra234-gpuvm.dts
        ./tegra234-gpuvm-base.dtsi
        ./tegra234-gpuvm-memory.dtsi
        ./tegra234-gpuvm-proxies.dtsi
        ./tegra234-gpuvm-display.dtsi
        ./tegra234-gpuvm-engines.dtsi
        ./tegra234-gpuvm-dummies.dtsi
        ./generated
      ];
    };
    # Build-platform tools: preprocesses + compiles a device tree (arch-agnostic
    # text) at build time, so it runs on the builder -- buildPackages makes `gcc`
    # the native compiler in a cross build.
    nativeBuildInputs = [
      pkgs.buildPackages.dtc
      pkgs.buildPackages.gcc
      pkgs.buildPackages.xxd
    ];
    buildPhase =
      let
        kernel = config.boot.kernelPackages.kernel;
        mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
        # Stock R36.5 P3737/P3701 AGX DCB pin (full payload, not just the
        # embedded version string -- a wrong-board blob can carry a
        # valid-looking version with foreign SOR/connector routing).
        dcbSha256 = "e0d92e6dbf1ffef266cfd2e192847e76f8d88c19c55430f2f5d4aaf69494a2fc";
        dcbBytes = "8407";
      in
      ''
        # $CC = stdenv's compiler (triple-prefixed under cross); -E only
        # preprocesses, so the target triple is irrelevant to the text output.
        $CC -E -nostdinc -undef -D__DTS__ ${expDtDefines}-x assembler-with-cpp \
          -I${mainInc} \
          -I${./nv-dt-bindings} \
          -I. \
          tegra234-gpuvm.dts > preprocessed.dts
        dtc -I dts -O dtb -o tegra234-gpuvm.dtb preprocessed.dts
      ''
      # DCB gate only applies when the display node is present. The host1x
      # experiment modes drop it (-DEXP_DROP_DISPLAY), so the skip is keyed on
      # the same eval-time `dropDisplay` flag that drops the node -- NOT on
      # fdtget's exit code, which would silently no-op the check if the node
      # were ever renamed/moved in a display-on build.
      + lib.optionalString (!dropDisplay) ''
        # Verify the DCB payload that actually landed in the DTB against the
        # pinned stock AGX blob; fail the build on any drift. The display node
        # is present in this build, so the check is mandatory: if it can't be
        # extracted (renamed/moved, or fdtget missing) the supply-chain gate
        # must fail loudly rather than silently skip.
        if ! fdtget tegra234-gpuvm.dtb \
             /platform-bus@70000000/display@13800000 nvidia,dcb-image >/dev/null 2>&1; then
          echo "DCB gate: display@13800000/nvidia,dcb-image not found in DTB" >&2
          echo "(node renamed/moved, or fdtget missing) -- refusing to skip the check" >&2
          exit 1
        fi
        # -t bx prints space-separated hex bytes, UNPADDED (e.g. `0 d 55 aa`),
        # so zero-pad each to two digits before xxd -r -p folds the whole
        # payload back to binary in one pass (replaces a ~16k-exec printf loop).
        fdtget -t bx tegra234-gpuvm.dtb \
          /platform-bus@70000000/display@13800000 nvidia,dcb-image \
          | tr -s ' \n' '\n' | grep . | sed 's/^\(.\)$/0\1/' | xxd -r -p > dcb.bin
        dcbLen=$(wc -c < dcb.bin)
        dcbHash=$(sha256sum dcb.bin | cut -d' ' -f1)
        if [ "$dcbLen" != "${dcbBytes}" ] || [ "$dcbHash" != "${dcbSha256}" ]; then
          echo "DCB payload drifted: $dcbLen bytes, sha256 $dcbHash" >&2
          echo "expected ${dcbBytes} bytes, sha256 ${dcbSha256}" >&2
          exit 1
        fi
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

  options.ghaf.hardware.nvidia.passthroughs.gpu_vm.host1xExperiment = lib.mkOption {
    type = lib.types.enum [
      "off"
      "compute-no-host1x"
      "display-no-host1x"
      "compute-with-host1x"
    ];
    default = "off";
    description = ''
      Branch-only host1x-ownership experiment selector (experiment/orin-two-vm-host1x).
      "off" reproduces the validated combined-gpuvm build. "compute-no-host1x"
      strips host1x/shim/media/display for the GPU-compute feasibility gate.
      "display-no-host1x" strips host1x/shim/media/gpu and forces NVKMS no-syncpt
      mode for the software-display feasibility gate. "compute-with-host1x" is the
      concurrent-test GPU VM: KEEPS host1x/shim/media/gpu, drops display, and
      shrinks guest RAM bank1 to release the scanout carveout for the GUI VM.
      Never promote to a target.
    '';
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
      {
        # Only one VM may open /dev/dce-host and drain the single DCE event ring
        # (patch 0002's gate). gpu-vm sets GHAF_DCE_GUEST unless dropDisplay;
        # disp-vm sets it whenever enabled -- so the two must not overlap.
        assertion = !((!dropDisplay) && config.ghaf.hardware.nvidia.passthroughs.disp_vm.enable);
        message = "gpu-vm still owns the display (host1xExperiment = \"${exp}\") while disp_vm is enabled: both would set GHAF_DCE_GUEST and race the DCE ring. Use a display-dropping host1xExperiment mode or disable disp_vm.";
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
        ) allDevs;
        ExecStart = map (
          d: "${pkgs.bash}/bin/bash -c \"echo ${d} > /sys/bus/platform/drivers/vfio-platform/bind\""
        ) allDevs;
      };
    };
    systemd.services."microvm@gpu-vm" = {
      after = [ "bindGpuVm.service" ];
      # Exclusive DCE ownership (opt-in): the QEMU DCE bridge is created only when
      # GHAF_DCE_GUEST=1 (ghaf-qemu-bpmp patch 0002). A display-capable GPU-VM opts
      # in; a display-less one leaves it unset -> never opens /dev/dce-host, so it
      # can't steal disp-vm's DCE events.
      environment = lib.mkIf (!dropDisplay) { GHAF_DCE_GUEST = "1"; };
    };

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
          # DRM userspace: this nvidia-drm build has no fbdev support, so there's no
          # fbcon to trigger a modeset and the panel stays dark. Ship modetest so a
          # modeset can be driven from userspace until a compositor runs here.
          environment.systemPackages =
            let
              # Forces plain no-modifier GBM window surfaces; see the shim source for
              # why the modifier path EGL_BAD_ALLOCs on this guest.
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
              # Graphics ABI verification: eglinfo/eglgears prove the NVIDIA EGL impl
              # and a GA10B renderer string, drm_info maps render/KMS nodes.
              pkgs.mesa-demos
              pkgs.drm_info
            ];

          # NVIDIA/Jetson graphics userspace (EGL/GLES/GBM) via /run/opengl-driver,
          # mirroring jetpack-nixos modules/graphics.nix. The guest can't enable
          # hardware.nvidia-jetpack (BYO kernel), so lift just the userspace wiring.
          # l4t-3d-core ships the GL vendor libs; extras carry runtime deps
          # (nvrm/gbm/wayland/nvsci).
          hardware.graphics = {
            enable = true;
            # l4t-3d-core's bundled libnvidia-egl-gbm 1.1.0 shadowed by nixpkgs egl-gbm
            # 1.1.3: the 1.1.0 EGL GBM platform heap-corrupts eglInitialize under mesa
            # 26's libgbm (surfaceless/device platforms are fine). First path wins in
            # the join; drop the l4t json so the platform module isn't loaded twice.
            package = pkgs.symlinkJoin {
              name = "l4t-3d-core-egl-gbm-1.1.3";
              paths = [
                # single-device fallback: on Tegra the EGL device's DRM node (tegra-drm)
                # never path-matches the gbm fd (nvidia-drm), so stock matching always
                # fails eglInitialize on GBM.
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
                # l4t-gbm minus its bundled libnvidia-egl-gbm 1.1.0 (and platform
                # json): egl-gbm 1.1.3 in `package` provides that library; keep only
                # the nvidia-drm_gbm backend.
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

          # Guest kernel = vanilla 6.12 + jetpack OOT overlay (BYO-kernel), GPU
          # passthrough patches applied to nvidia-oot-modules.
          boot.kernelPackages = lib.mkForce (
            (pkgs.linuxPackages_6_12.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
              _final: prev: {
                nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
                  patches =
                    (o.patches or [ ])
                    ++ [
                      ./patches/0001-gpu-add-support-for-passthrough.patch
                      ./patches/0002-add-support-for-gpu-display-passthrough.patch
                      ./patches/0003-add-support-for-display-passthrough.patch
                      # Force NISO display surfaces (channel pushbuffer, notifier,
                      # semaphores) contiguous so they land in the 1:1 physical carveout
                      # the host DCE R5 can resolve -- else the window channel never
                      # advances ("waiting for GPU progress", NVC67E).
                      ./patches/0005-force-niso-display-surfaces-contiguous.patch
                      # Address policy for everything handed to the host-owned DCE R5
                      # (inst-mem base, channel pushbuffers, ctxdma FrameAddrs): CPU
                      # physical (1:1 GPA=HPA carveout), offset into the native display
                      # high-IOVA range (raw physicals abort the R5's UPDATE), absolute
                      # ctxdma Limit computed after the offset. The host maps
                      # hi->carveout in the display SMMU domains and retags the scanout
                      # readers' MC SIDs (dce-iso-anchor).
                      ./patches/0006-dce-addresses-cpu-phys-high-iova.patch
                      # DP++ dual-mode: a passive HDMI adapter asserts HPD but has no DP
                      # sink; trust RM's DDC/LOAD detection over the DP lib's HPD-only
                      # guess so detection falls through to the TMDS partner displayId
                      # where the sink really is.
                      ./patches/0008-fix-dual-mode-honor-rm-connect-state.patch
                      # Core notifier: plain WRITE, never WRITE_AWAKEN -- the awaken
                      # rides the DCE async event path the guest can't receive and the
                      # R5 aborts the whole completion write. Dropping this (even with
                      # the ch3 relay live) stops flips completing entirely; keep plain WRITE.
                      ./patches/0009-core-notifier-plain-write-no-awaken.patch
                      # Boot hotplug: a panel connected at boot produces no HPD edge, so
                      # the host DCE never sends the hotplug event and the SOR is never
                      # assigned (dark until manual replug). Schedule the deferred
                      # hotplug work once at init.
                      ./patches/0020-synthesize-boot-hotplug-long-pulse.patch
                      # Drop the host DCE R5's flip-completion event: it lands ~130ms
                      # after kickoff (~8-10fps ceiling), not a usable per-flip signal
                      # under passthrough. Completion is driven by 0013's vblank
                      # qualification instead.
                      ./patches/0010-dce-drop-r5-completion-event.patch
                      # Window-channel completion notifier: plain WRITE, never
                      # WRITE_AWAKEN -- same R5 abort as the core channel (0009).
                      # Native-R5 60fps completion (WRITE_AWAKEN gated on the active
                      # primary) is blocked on an intermittent window-channel
                      # BEGUN->FINISHED latch failure at 60fps kickoff (closed R5
                      # firmware); see branch native-r5-experimental.
                      ./patches/0011-window-notifier-plain-write.patch
                      # Complete each committed flip 2 physical vblank callbacks after
                      # it was armed -- a scanout-latch margin, tear-free at ~30fps. The
                      # R5-latch-reliable path while native-R5 60fps stays blocked on
                      # closed R5/window-channel firmware.
                      ./patches/0013-drm-vblank-flip-completion.patch
                    ]
                    # Experiment B (display-no-host1x): NVKMS no-syncpt path.
                    # Branch-scoped — never globally disable syncpoints.
                    ++ lib.optional displayOnly ./patches/0021-nvkms-force-no-syncpt-support.patch;
                  # DCE display proxy (guest side): redirect the guest's DCE IPC through
                  # the shared MMIO window and skip the R5 bootstrap (R5 is host-owned).
                  # The hook patch targets the nvidia-oot project root (no nvidia-oot/
                  # prefix), so apply it scoped to nvidia-oot/; splice the guest proxy in
                  # as its own obj-m .ko (it links tegra-dce's exports, so it must build
                  # inside nvidia-oot).
                  postPatch = (o.postPatch or "") + ''
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0001-dce-virt-hooks.patch}
                    # Reverse-doorbell stage 2: export the async-event injector the guest
                    # proxy uses to deliver relayed ch3 events to nvdisplay's RM_EVENT client.
                    patch -p1 -d nvidia-oot < ${../../common/dce-virt-common/patches/0002-dce-client-ipc-inject.patch}
                    install -D ${../../common/dce-virt-common/sources/drivers/platform/tegra/dce-guest-proxy/dce-guest-proxy.c} \
                      nvidia-oot/drivers/platform/tegra/dce/dce-guest-proxy.c
                    echo 'obj-m += dce-guest-proxy.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile
                  '';
                });
              }
            )
          );
          # nvidia-drm.modeset=1 + fbdev=1: bring up the NVIDIA KMS layer and fbcon.
          # fbcon drawing to the panel is the modeset TRIGGER that makes nvdisplay
          # bring up display -> DCE handshake via proxy -> scanout. Without a modeset
          # request the device binds but stays idle.
          boot.kernelParams = [
            "clk_ignore_unused"
            "pd_ignore_unused"
            "nvidia-drm.modeset=1"
            # Never auto-disable vblank interrupts. nvidia-drm disables them when the
            # last flip completes; under the DCE proxy each re-enable is a synchronous
            # EVENT_SET_NOTIFICATION RPC to the R5 (~10ms) plus a slow stream restart,
            # quantizing flips to ~122ms (~8 fps). With the vblank stream always on the
            # R5 emits completions at the 60Hz vblank cadence.
            "drm.vblankoffdelay=0"
            # NB: this nvidia-drm build REJECTS fbdev, so there's no fbcon and nothing
            # auto-requests a modeset -- the connector is detected but stays unlit until
            # a DRM client sets a mode. Kept only in case a driver that supports it is
            # used later.
            "nvidia-drm.fbdev=1"
            # NOTE: do NOT add "video=DP-1:...e". The trailing 'e' forces the connector
            # on (DRM_FORCE_ON) -> nvidia-drm sets forceConnected and nvDpyGetDynamicData
            # short-circuits to "connected" for the DisplayPort displayId before it
            # consults the DP lib or RM. The AGX DP port is DP++ dual-mode (0x100
            # SOR_DP_A + 0x200 SINGLE_TMDS_A are one connector, two encoders); forcing
            # the DP encoder on stops connector detect there, so the TMDS partner --
            # where a passive HDMI adapter's sink lives -- is never probed and every
            # EDID read fails on AUX forever.
          ];

          assertions = [
            {
              assertion =
                (lib.elem "clk_ignore_unused" config.boot.kernelParams)
                && (lib.elem "pd_ignore_unused" config.boot.kernelParams);
              message = "gpu-vm guest must boot with both clk_ignore_unused and pd_ignore_unused, or it can power off clocks/domains the host still uses.";
            }
          ];

          # OOT GPU drivers don't autoload from a DT match, so load them explicitly --
          # else nothing binds gpu@17000000, no /dev/nvgpu|nvmap|nvhost-*, and CUDA's
          # NvRmMemMgr init fails.
          boot.extraModulePackages = [ config.boot.kernelPackages.nvidia-oot-modules ];
          boot.kernelModules =
            # nvmap/host1x(sw)/nvhost/nvgpu: the GPU compute stack. host1x here is the
            # software module satisfying nvgpu's symbols, not the physical VFIO device.
            # Dropped in the display-only VM (no GA10B there).
            lib.optionals (!displayOnly) [
              "nvmap"
              "host1x"
              "nvhost"
              "nvgpu"
            ]
            # DCE display proxy (guest): tegra-dce binds the synthetic dce node
            # (dce-virtual-pa, no reg) in proxy mode; dce-guest-proxy binds the
            # nvidia,dce-guest-proxy node, ioremaps the shared window and installs the
            # send redirect. Neither autoloads from a DT match, so load explicitly.
            # dce-guest-proxy links tegra-dce's redirect symbol, so tegra-dce is ordered first.
            #
            # Display KMS stack: gives the guest a /dev/dri KMS device + crtcs for
            # display@13800000. With nvidia-drm.modeset=1 + fbdev=1 fbcon draws to the
            # panel -> the modeset that brings up display -> DCE handshake via proxy.
            # nvidia-drm pulls nvidia-modeset + nvidia via deps. Dropped in compute-only.
            # nvmap appears in both arms deliberately (list de-dups) so either arm alone
            # is complete.
            ++ lib.optionals (!dropDisplay) [
              "nvmap"
              "tegra-dce"
              "dce-guest-proxy"
              "nvidia-modeset"
              "nvidia-drm"
            ];

          # gk20a loads falcon microcode from /lib/firmware at probe; without it the
          # probe times out (-110). Ship the L4T GPU firmware.
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
