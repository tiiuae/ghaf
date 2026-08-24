# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Capability-parameterized Orin GPU/display guest module.
{
  lib,
  cap,
  dtb,
  dtbName ? "tegra234-gpuvm.dtb",
  vfioArgs,
  sourcesPatch,
  srcDir ? ../gpu-vm,
}:
let
  payload = (import ./default.nix { inherit lib; }).mkPayload cap;
in
{ config, pkgs, ... }:
let
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  # L4T EGL rejects modifier-backed GBM surfaces.
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
  # Stable nvdisplay node; host1x also registers a connector-less DRM card.
  displayCard = "/dev/dri/by-path/platform-66200000.display-card";
in
{
  environment.systemPackages = [
    pkgs.libdrm
    kmscube-wrapped
    pkgs.mesa-demos
    pkgs.drm_info
  ];

  # Keep a mode active when no compositor owns the display.
  systemd.services.kms-owner = lib.mkIf (cap.display && !config.ghaf.graphics.cosmic.enable) {
    description = "Hold DRM master on the nvdisplay card so the panel stays lit";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    wants = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -e ${displayCard} ] && exit 0; sleep 1; done; exit 1'";
      # Keep stdin open; kmscube exits on /dev/null POLLHUP.
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/sleep infinity | ${kmscube-wrapped}/bin/kmscube -D ${displayCard}'";
      Restart = "always";
      RestartSec = "2";
    };
  };

  # Pair the BYO kernel with JetPack graphics userspace.
  hardware.graphics = {
    enable = true;
    # Keep Mesa for Wayland clients; COSMIC renders through the NVIDIA GBM node.
    extraPackages = [
      # Replace incompatible L4T EGL GBM/Wayland platform libraries.
      (pkgs.symlinkJoin {
        name = "l4t-3d-core-egl-gbm-1.1.3";
        paths = [
          (pkgs.egl-gbm.overrideAttrs (o: {
            patches = (o.patches or [ ]) ++ [
              (srcDir + "/patches/userspace/egl-gbm-single-device-fallback.patch")
            ];
          }))
          pkgs.egl-wayland
          pkgs.nvidia-jetpack.l4t-3d-core
        ];
        postBuild = ''
          rm -f $out/share/egl/egl_external_platform.d/nvidia_gbm.json
        '';
      })
    ]
    ++ (with pkgs.nvidia-jetpack; [
      l4t-core
      l4t-cuda
      l4t-nvsci
    ])
    ++ [
      (pkgs.symlinkJoin {
        name = "l4t-wayland-sans-egl-wayland";
        paths = [ pkgs.nvidia-jetpack.l4t-wayland ];
        postBuild = ''
          rm -f $out/lib/libnvidia-egl-wayland.so*
          rm -f $out/share/egl/egl_external_platform.d/nvidia_wayland.json
        '';
      })
    ]
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
  environment.etc."egl/egl_external_platform.d".source =
    "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

  # Apply the GPU/display passthrough stack to the BYO guest kernel.
  boot.kernelPackages = lib.mkForce (
    (pkgs.linuxPackages_6_12.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
      _final: prev: {
        nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
          patches =
            (o.patches or [ ])
            ++ [
              "${support}/patches/nvidia-oot/gpu-display/0001-gpu-add-support-for-passthrough.patch"
              "${support}/patches/nvidia-oot/gpu-display/0002-add-support-for-gpu-display-passthrough.patch"
              "${support}/patches/nvidia-oot/gpu-display/0003-add-support-for-display-passthrough.patch"
              # Keep DCE-visible NISO allocations in the identity carveout.
              "${support}/patches/nvidia-oot/gpu-display/0005-force-niso-display-surfaces-contiguous.patch"
              # Translate guest physical display addresses into the native high IOVA.
              "${support}/patches/nvidia-oot/gpu-display/0006-dce-addresses-cpu-phys-high-iova.patch"
              # Let RM select the TMDS partner behind passive DP++ adapters.
              "${support}/patches/nvidia-oot/gpu-display/0008-fix-dual-mode-honor-rm-connect-state.patch"
              # Core completion requires plain WRITE, not WRITE_AWAKEN.
              "${support}/patches/nvidia-oot/gpu-display/0009-core-notifier-plain-write-no-awaken.patch"
              # Synthesize the missing HPD edge for a display connected at boot.
              "${support}/patches/nvidia-oot/gpu-display/0020-synthesize-boot-hotplug-long-pulse.patch"
              # Keep the stock R5 FLIP_OCCURRED path as the sole completion owner.
              "${support}/patches/nvidia-oot/gpu-display/0011-window-notifier-plain-write.patch"
              # Keep the R5's flip-completion binding across modesets, or the
              # desktop session after the greeter never sees a completion.
              "${support}/patches/nvidia-oot/gpu-display/0024-nvkms-keep-flip-completion-binding.patch"
              # Kernel 6.12.103 removed drm_fb_helper_alloc_info(); without this
              # the tegra fbdev in nvidia-oot does not compile at all.
              "${support}/patches/nvidia-oot/gpu-display/0025-tegra-fbdev-use-core-allocated-fb-info.patch"
            ]
            # disp-vm has no guest-owned host1x syncpoints.
            ++ lib.optional payload.noSyncpointPatch "${support}/patches/nvidia-oot/gpu-display/0021-nvkms-force-no-syncpt-support.patch";
          # Build the guest DCE relay inside nvidia-oot for tegra-dce symbols.
          postPatch = (o.postPatch or "") + ''
            patch -p1 -d nvidia-oot < ${support}/patches/nvidia-oot/dce/0001-dce-virt-hooks.patch
            patch -p1 -d nvidia-oot < ${support}/patches/nvidia-oot/dce/0002-dce-client-ipc-inject.patch
            install -D ${support}/sources/nvidia-oot/drivers/platform/tegra/dce-guest-proxy/dce-guest-proxy.c \
              nvidia-oot/drivers/platform/tegra/dce/dce-guest-proxy.c
            echo 'obj-m += dce-guest-proxy.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile
          '';
        });
      }
    )
  );
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "nvidia-drm.modeset=1"
    # Avoid synchronous DCE vblank disable/re-enable cycles between flips.
    "drm.vblankoffdelay=0"
  ];

  assertions = [
    {
      assertion =
        (lib.elem "clk_ignore_unused" config.boot.kernelParams)
        && (lib.elem "pd_ignore_unused" config.boot.kernelParams);
      message = "gpu-vm guest must boot with both clk_ignore_unused and pd_ignore_unused, or it can power off clocks/domains the host still uses.";
    }
  ];

  # NVIDIA OOT modules do not autoload from the guest DT.
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia-oot-modules ];
  boot.kernelModules = payload.guestKernelModules;

  hardware.firmware = [ pkgs.nvidia-jetpack.l4t-firmware ];

  boot.kernelPatches = [
    {
      name = "tegra fixed chip id";
      patch = "${support}/patches/linux/0004-tegra-fixed-chip-id.patch";
    }
    {
      name = "bpmp-virt proxy drivers";
      patch = sourcesPatch;
    }
    {
      name = "bpmp-virt core hooks";
      patch = "${support}/patches/linux/bpmp/0001-bpmp-virt-hooks-6.12.patch";
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
    "${dtb}/${dtbName}"
  ]
  ++ vfioArgs;
}
