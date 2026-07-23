# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cap-parameterized Orin guest NixOS module, shared by gpu-vm (and gui-vm).
# Extracted verbatim from gpu-vm/default.nix's guest extraModules block; the only
# changes are that the `exp`-derived booleans are replaced by `cap` fields and the
# guest kernel-module list / no-syncpoint patch come from `mkPayload cap`. Patch and
# source files still live in gpu-vm/, referenced via `srcDir` (defaults to ../gpu-vm);
# the ../../common/... paths resolve identically from here (payload/ and gpu-vm/ are
# both under passthrough/). `sourcesPatch` is the host-scope bpmp-virt sources patch
# (guest `config` shadows the host, so it must be threaded in from the caller).
{
  lib,
  cap,
  dtb,
  vfioArgs,
  sourcesPatch,
  srcDir ? ../gpu-vm,
}:
let
  payload = (import ./default.nix { inherit lib; }).mkPayload cap;
in
{ config, pkgs, ... }:
let
  # Forces plain no-modifier GBM window surfaces; see the shim source for
  # why the modifier path EGL_BAD_ALLOCs on this guest.
  gbm-nomod-shim = pkgs.runCommandCC "gbm-nomod-shim" { } ''
    mkdir -p $out/lib
    $CC -O2 -fPIC -shared -o $out/lib/gbm-nomod-shim.so \
      ${srcDir + "/sources/gbm-nomod-shim.c"} -ldl
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
  # Stable by-path node for the nvdisplay KMS card (66200000.display -> card0).
  # Avoids the card0/card1 lottery: card1 is the connector-less host1x tegra-drm.
  displayCard = "/dev/dri/by-path/platform-66200000.display-card";
in
{
  # DRM userspace: this nvidia-drm build has no fbdev support, so there's no
  # fbcon to trigger a modeset and the panel stays dark. Ship modetest so a
  # modeset can be driven from userspace until a compositor runs here.
  environment.systemPackages = [
    pkgs.libdrm
    kmscube-wrapped
    # Graphics ABI verification: eglinfo/eglgears prove the NVIDIA EGL impl
    # and a GA10B renderer string, drm_info maps render/KMS nodes.
    pkgs.mesa-demos
    pkgs.drm_info
  ];

  # Persistent KMS master. This nvidia-drm build has no fbdev, so nothing holds
  # a mode after boot and the panel stays dark even though DP-1 is connected --
  # a mode set by a client that exits drops the screen. Run the (shim-wrapped)
  # kmscube on the nvdisplay card to own DRM master and keep the panel lit; it
  # doubles as the Phase-4 visual proof (spinning cube). cap.display only
  # (gui-vm/disp-vm); compute-only gpu-vm never starts it. Restart=always covers
  # kmscube exiting on connector loss. Disabled once COSMIC is enabled: cosmic-comp
  # is then the real persistent DRM master, and two masters on one card conflict
  # (kmscube would steal the card and the desktop never lights). So the holder is
  # the no-compositor fallback (disp-vm bring-up); the gui-vm desktop supersedes it.
  systemd.services.gui-vm-kms-owner = lib.mkIf (cap.display && !config.ghaf.graphics.cosmic.enable) {
    description = "Hold DRM master on the nvdisplay card so the panel stays lit";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    wants = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      # nvidia-drm loads late (explicit boot.kernelModules), so the by-path node
      # may not exist at udev-settle; wait for it before kmscube.
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -e ${displayCard} ] && exit 0; sleep 1; done; exit 1'";
      # kmscube poll()s stdin for a quit-key. Under systemd stdin is /dev/null,
      # which returns POLLHUP immediately -> kmscube reads EOF and quits with
      # "user interrupted!" ~instantly (a foreground pty stdin blocks, so a manual
      # run sustains). Pipe `sleep infinity` into stdin: an open pipe with no
      # writer-close and no data, so the stdin poll never fires and kmscube runs
      # until a real signal / DRM error.
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/sleep infinity | ${kmscube-wrapped}/bin/kmscube -D ${displayCard}'";
      Restart = "always";
      RestartSec = "2";
    };
  };

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
            (srcDir + "/patches/userspace/egl-gbm-single-device-fallback.patch")
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
              (srcDir + "/patches/0001-gpu-add-support-for-passthrough.patch")
              (srcDir + "/patches/0002-add-support-for-gpu-display-passthrough.patch")
              (srcDir + "/patches/0003-add-support-for-display-passthrough.patch")
              # Force NISO display surfaces (channel pushbuffer, notifier,
              # semaphores) contiguous so they land in the 1:1 physical carveout
              # the host DCE R5 can resolve -- else the window channel never
              # advances ("waiting for GPU progress", NVC67E).
              (srcDir + "/patches/0005-force-niso-display-surfaces-contiguous.patch")
              # Address policy for everything handed to the host-owned DCE R5
              # (inst-mem base, channel pushbuffers, ctxdma FrameAddrs): CPU
              # physical (1:1 GPA=HPA carveout), offset into the native display
              # high-IOVA range (raw physicals abort the R5's UPDATE), absolute
              # ctxdma Limit computed after the offset. The host maps
              # hi->carveout in the display SMMU domains and retags the scanout
              # readers' MC SIDs (dce-iso-anchor).
              (srcDir + "/patches/0006-dce-addresses-cpu-phys-high-iova.patch")
              # DP++ dual-mode: a passive HDMI adapter asserts HPD but has no DP
              # sink; trust RM's DDC/LOAD detection over the DP lib's HPD-only
              # guess so detection falls through to the TMDS partner displayId
              # where the sink really is.
              (srcDir + "/patches/0008-fix-dual-mode-honor-rm-connect-state.patch")
              # Core notifier: plain WRITE, never WRITE_AWAKEN -- the awaken
              # rides the DCE async event path the guest can't receive and the
              # R5 aborts the whole completion write. Dropping this (even with
              # the ch3 relay live) stops flips completing entirely; keep plain WRITE.
              (srcDir + "/patches/0009-core-notifier-plain-write-no-awaken.patch")
              # Boot hotplug: a panel connected at boot produces no HPD edge, so
              # the host DCE never sends the hotplug event and the SOR is never
              # assigned (dark until manual replug). Schedule the deferred
              # hotplug work once at init.
              (srcDir + "/patches/0020-synthesize-boot-hotplug-long-pulse.patch")
              # Drop the host DCE R5's flip-completion event: it lands ~130ms
              # after kickoff (~8-10fps ceiling), not a usable per-flip signal
              # under passthrough. Completion is driven by 0013's vblank
              # qualification instead.
              (srcDir + "/patches/0010-dce-drop-r5-completion-event.patch")
              # Window-channel completion notifier: plain WRITE, never
              # WRITE_AWAKEN -- same R5 abort as the core channel (0009).
              # Native-R5 60fps completion (WRITE_AWAKEN gated on the active
              # primary) is blocked on an intermittent window-channel
              # BEGUN->FINISHED latch failure at 60fps kickoff (closed R5
              # firmware); see branch native-r5-experimental.
              (srcDir + "/patches/0011-window-notifier-plain-write.patch")
              # Complete each committed flip 2 physical vblank callbacks after
              # it was armed -- a scanout-latch margin, tear-free at ~30fps. The
              # R5-latch-reliable path while native-R5 60fps stays blocked on
              # closed R5/window-channel firmware.
              (srcDir + "/patches/0013-drm-vblank-flip-completion.patch")
            ]
            # Experiment B (display-no-host1x): NVKMS no-syncpt path.
            # Branch-scoped — never globally disable syncpoints.
            ++ lib.optional payload.noSyncpointPatch (
              srcDir + "/patches/0021-nvkms-force-no-syncpt-support.patch"
            );
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
  # nvmap/host1x(sw)/nvhost/nvgpu: the GPU compute stack (host1x here is the
  # software module satisfying nvgpu's symbols, not the physical VFIO device),
  # plus the DCE proxy + KMS stack (tegra-dce/dce-guest-proxy/nvidia-modeset/
  # nvidia-drm) for the display arm. Neither autoloads from a DT match, so load
  # explicitly; the list de-dups nvmap across both arms. Cap-derived so each
  # payload gets exactly the modules its engines need.
  boot.kernelModules = payload.guestKernelModules;

  # gk20a loads falcon microcode from /lib/firmware at probe; without it the
  # probe times out (-110). Ship the L4T GPU firmware.
  hardware.firmware = [ pkgs.nvidia-jetpack.l4t-firmware ];

  boot.kernelPatches = [
    {
      name = "tegra fixed chip id";
      patch = srcDir + "/patches/0004-tegra-fixed-chip-id.patch";
    }
    {
      name = "bpmp-virt proxy drivers";
      patch = sourcesPatch;
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
    "${dtb}/tegra234-gpuvm.dtb"
  ]
  ++ vfioArgs;
}
