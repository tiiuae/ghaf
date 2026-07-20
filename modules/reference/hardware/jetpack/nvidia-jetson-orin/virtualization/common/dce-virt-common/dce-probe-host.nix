# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# DCE display-proxy HOST integration (AGX only).
#
# Companion to gpu-vm's guest overlay (../../passthrough/gpu-vm). Guest takes
# display@13800000 and drives the panel via a synthetic DCE proxy; HOST keeps
# the REAL dce@d800000 and owns its R5. This module makes the host:
#   - stay headless (no COSMIC/graphics, display RM blacklisted) so the host
#     CCPLEX never touches display@13800000 -- only guest CCPLEX + host R5 share it;
#   - force-load tegra-dce so it bootstraps and owns the real DCE R5;
#   - build + load dce-host-proxy .ko and inject a "nvidia,dce-host-proxy" DT
#     node so the proxy binds and creates /dev/dce-host (QEMU DCE bridge relays
#     the guest's DCE IPC through it to the R5);
#   - keep gpu_vm ENABLED (unlike the Phase-0 spike, which forced it off).
#
# AGX-only: imported from agx/orin-agx.nix, never hoisted into a shared orin.nix.
{
  lib,
  pkgs,
  ...
}:
let
  # Bare "nvidia,dce-host-proxy" node so the platform driver binds and creates
  # /dev/dce-host. Driver reads no reg/vpa (relays via tegra-dce's exported
  # CPU_RM client API), so the node only needs the compatible. Mirrors
  # bpmp-virt-host's bpmp_host_overlay: a DT overlay, not a patch against
  # NVIDIA's device trees.
  dceHostOverlay = pkgs.writeText "dce_host_overlay.dts" ''
    /dts-v1/;
    /plugin/;
    / {
        overlay-name = "DCE host proxy";
        compatible = "nvidia,tegra234";
        fragment@0 {
            target-path = "/";
            __overlay__ {
                dce_host_proxy: dce_host_proxy {
                    compatible = "nvidia,dce-host-proxy";
                    status = "okay";
                };
            };
        };
    };
  '';
in
{
  _file = ./dce-probe-host.nix;

  # Host display driver blacklisted (headless), so nothing in Linux claims the
  # display clocks/power-domains (dpaux0, SOR, disp, DP PLLs) or the DCE. Then
  # clk_disable_unused()/genpd_disable_unused() at late_initcall gate them off as
  # "unused" -- but the host-owned DCE R5 needs them ON for DP-AUX (read EDID) and
  # to drive the SOR (output). Symptom when gated: DP reads "connected" (HPD
  # survives) but EDID is 0 bytes (AUX unclocked) and no mode is set (SOR
  # unclocked) -> no signal. Keep unused clocks + power-domains on.
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
  ];

  # Headless: nothing may bring up COSMIC/graphics and register a CPU_RM display
  # client on the host; the host CCPLEX must never program display@13800000
  # (it belongs to the guest).
  ghaf.profiles.graphics.enable = lib.mkForce false;

  # Host kernel = base jetpack-nixos for orin-agx
  # (pkgs.nvidia-jetpack.kernelPackages) + dce-host-proxy spliced into
  # nvidia-oot-modules. mkForce required: hardware.nvidia-jetpack already sets
  # boot.kernelPackages at normal priority.
  boot.kernelPackages = lib.mkForce (
    (pkgs.nvidia-jetpack.kernelPackages.extend pkgs.nvidia-jetpack.kernelPackagesOverlay).extend (
      _final: prev: {
        nvidia-oot-modules = prev.nvidia-oot-modules.overrideAttrs (o: {
          # nvidia-oot-modules' src is the combined l4t-oot-modules-sources tree
          # (nvidia-oot/, nvgpu/, nvdisplay/, ... each under its project name).
          # dce-host-proxy links tegra-dce's EXPORT_SYMBOL'd DCE client API, so it
          # must build INSIDE nvidia-oot (not the kernel tree). Flatten its source
          # into dce/ (whose Makefile ccflags already resolve the public
          # dce-client-ipc.h include) and add as its own obj-m .ko.
          # dtc + xxd: dce-iso-anchor embeds its runtime DT overlay as a C array
          # (compiled with -@ so &smmu_iso resolves against the live tree's
          # __symbols__ at of_overlay_fdt_apply time).
          nativeBuildInputs = (o.nativeBuildInputs or [ ]) ++ [
            pkgs.buildPackages.dtc
            pkgs.buildPackages.unixtools.xxd
          ];
          postPatch = (o.postPatch or "") + ''
            install -D ${./sources/drivers/platform/tegra/dce-host-proxy/dce-host-proxy.c} \
              nvidia-oot/drivers/platform/tegra/dce/dce-host-proxy.c
            install -D ${./sources/drivers/platform/tegra/dce-host-proxy/dce-host-proxy.h} \
              nvidia-oot/drivers/platform/tegra/dce/dce-host-proxy.h
            echo 'obj-m += dce-host-proxy.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile

            install -D ${./sources/drivers/platform/tegra/dce-iso-anchor/dce-iso-anchor.c} \
              nvidia-oot/drivers/platform/tegra/dce/dce-iso-anchor.c
            dtc -@ -I dts -O dtb -o dce-iso-anchor.dtbo \
              ${./sources/drivers/platform/tegra/dce-iso-anchor/dce-iso-anchor.dts}
            xxd -i -n dce_iso_anchor_dtbo dce-iso-anchor.dtbo \
              > nvidia-oot/drivers/platform/tegra/dce/dce-iso-anchor-dtbo.h
            echo 'obj-m += dce-iso-anchor.o' >> nvidia-oot/drivers/platform/tegra/dce/Makefile
          '';
        });
      }
    )
  );

  # boot.extraModulePackages not needed: hardware.nvidia-jetpack already sets
  # `boot.extraModulePackages = [ config.boot.kernelPackages.nvidia-oot-modules ]`
  # for jetpackAtLeast "6", resolving against the forced boot.kernelPackages
  # above, so dce-host-proxy.ko rides along automatically.

  # Blacklist the host display RM stack so no CPU_RM display client registers
  # and the host never programs display@13800000. tegra-dce deliberately NOT
  # blacklisted (host must keep bootstrapping/owning the DCE R5). gpu-vm's
  # default.nix also blacklists nvgpu/host1x; the lists merge.
  boot.blacklistedKernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_drm"
    "tegra_drm"
  ];

  # nvidia-oot modules do NOT autoload from a DT compatible match. Force-load
  # tegra-dce (binds real d800000.dce, drives R5 bootstrap to LOCKED) and
  # dce-host-proxy (binds the injected node, creates /dev/dce-host).
  # dce-host-proxy links tegra-dce's symbols, so modprobe orders tegra-dce first.
  boot.kernelModules = [
    "tegra-dce"
    "dce-host-proxy"
    # smmu_iso SID-1 anchor: translating domain for the FE's ISO scanout stream
    # with DCE high-IOVA -> carveout maps (else panel is lit-but-black under
    # passthrough). Applies its own DT overlay at load.
    "dce-iso-anchor"
  ];

  # /dev/dce-host is opened by patched QEMU (microvm user in kvm group) to relay
  # guest DCE IPC. Grant kvm group access, mirroring the bpmp-host / vfio rule
  # in gpu-vm's default.nix.
  services.udev.extraRules = ''
    KERNEL=="dce-host", GROUP="kvm", MODE="0660"
  '';

  hardware.deviceTree.enable = true;
  hardware.deviceTree.overlays = [
    {
      name = "dce_host_overlay";
      dtsFile = dceHostOverlay;
    }
  ];
}
