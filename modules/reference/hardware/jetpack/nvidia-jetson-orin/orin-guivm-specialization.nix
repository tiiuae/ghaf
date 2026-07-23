# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Small AArch64/Orin specialization for the canonical (x86-defaulted) guivm-base.
# Overrides only what guivm-base cannot infer on aarch64.
{ lib, pkgs, ... }:
let
  # Same shim kmscube uses (gpu-vm/sources): forces every gbm_surface_create*
  # to a plain no-modifier surface. On this L4T guest the NVIDIA EGL exposes
  # only the GBM/Wayland/X11/Surfaceless platforms (no EGL device platform), and
  # the modifier GBM path EGL_BAD_ALLOCs. cosmic-comp (smithay udev backend)
  # must go through GBM, so it needs this preloaded to create scanout surfaces.
  gbm-nomod-shim = pkgs.runCommandCC "gbm-nomod-shim" { } ''
    mkdir -p $out/lib
    $CC -O2 -fPIC -shared -o $out/lib/gbm-nomod-shim.so \
      ${./virtualization/passthrough/gpu-vm/sources/gbm-nomod-shim.c} -ldl
  '';
  # Fakes EGL_EXT_device enumeration so smithay (cosmic-comp) can match card0 to
  # an EGL device; Tegra's EGL BAD_ALLOCs eglQueryDevicesEXT. See the shim source.
  egl-device-shim = pkgs.runCommandCC "egl-device-shim" { } ''
    mkdir -p $out/lib
    $CC -O2 -fPIC -shared -o $out/lib/egl-device-shim.so \
      ${./virtualization/passthrough/gpu-vm/sources/egl-device-shim.c} -ldl
  '';
  cosmicPreload = "${gbm-nomod-shim}/lib/gbm-nomod-shim.so:${egl-device-shim}/lib/egl-device-shim.so";
in
{
  _file = ./orin-guivm-specialization.nix;

  # ponytail: guivm-base imports hardware-x86_64-guest-kernel, but that module's
  # entire `config` is `lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 { ... }`
  # (modules/hardware/x86_64-generic/kernel/guest/default.nix), so on aarch64 it
  # evaluates to {} - a no-op. No disabledModules needed; the Jetson combined
  # payload (hardware.definition.guivm.extraModules) sets the real guest kernel.
  config = {
    nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

    # Patch cosmic-comp so its KMS backend does NOT hard-require an EGLDevice
    # (EGL_EXT_device / eglQueryDevicesEXT), which the L4T/Tegra NVIDIA EGL
    # BAD_ALLOCs -> "Unable to find matching egl device" -> no output. The GBM
    # EGLDisplay + EGLContext render on the GA10B regardless; the patch degrades
    # the unused EGLDevice to Optional. See cosmic-comp-egl-device-optional.patch.
    nixpkgs.overlays = [
      (_final: prev: {
        cosmic-comp = prev.cosmic-comp.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [
            ./cosmic-comp-egl-device-optional.patch
          ];
        });
      })
    ];

    # Guest DT pins four CPUs; keep vcpu in sync (base defaults 6).
    microvm.vcpu = lib.mkForce 4;

    # gpu-screen-recorder is x86_64-only (modules/desktop/graphics/screen-recorder.nix
    # asserts pkgs.stdenv.isx86_64). COSMIC's screenRecorder defaults true and maps
    # to ghaf.graphics.screen-recorder.enable, so the aarch64 gui-vm guest would trip
    # that assertion. The Orin host disables it in orin.nix; the guest needs the same.
    ghaf.graphics.cosmic.screenRecorder.enable = lib.mkForce false;

    # Pin cosmic-comp to the GA10B render node. This cosmic-comp (1.1.0)
    # PREPENDS /dev/dri/ to COSMIC_RENDER_DEVICE, so it needs the BARE node name
    # ("renderD128"), not an absolute path -- an absolute value doubles to
    # /dev/dri//dev/dri/renderD128 -> "not found" -> software renderer -> no
    # output. But `ghaf.graphics.cosmic.renderDevice` is typed as an absolute
    # path (and cosmic/default.nix assigns it verbatim to COSMIC_RENDER_DEVICE),
    # so it can't carry a bare name. Set the option null (module skips the env)
    # and export the bare name directly. renderD128 = card0/nvgpu's render node
    # (card1, the host1x tegra-drm, is dropped from seat0 below).
    ghaf.graphics.cosmic.renderDevice = lib.mkForce null;
    systemd.services.greetd.environment.COSMIC_RENDER_DEVICE = "renderD128";
    environment.sessionVariables.COSMIC_RENDER_DEVICE = "renderD128";

    # Phase 6 boot-unblock. The Orin gui-vm has no fbcon (this nvidia-drm has no
    # fbdev), so tty1 is never visible. Two first-boot units then deadlock the
    # graphical boot and the panel stays dark:
    #
    # 1. user-provision-interactive runs a TTY wizard on /dev/tty1
    #    (before=greetd, requiredBy=multi-user.target) waiting for input that can
    #    never arrive without a console -> greetd/cosmic-comp never start.
    #    Disable it; the static `ghaf` user logs in via cosmic-greeter.
    ghaf.services.user-provisioning.enable = lib.mkForce false;

    # 2. The GIVC bluetooth/networkmanager dbus-proxies (modules/givc/guivm.nix)
    #    block forever on peer-VM sockets that do not exist in the single-gui-vm
    #    accelerated topology, restart-looping and holding multi-user.target
    #    (hence greetd). Drop them from the boot targets for this bring-up; the
    #    bt/nm applets return with the full desktop once those peers exist.
    systemd.services.dbus-proxy-bluetooth.wantedBy = lib.mkForce [ ];
    systemd.services.dbus-proxy-networkmanager.wantedBy = lib.mkForce [ ];

    # 3. cosmic-comp dies on init here: "eglQueryDevicesEXT: EGL_BAD_ALLOC ->
    #    Unable to find suitable EGL platform -> Failed to create EGLDisplay for
    #    /dev/dri/card0". Tegra's NVIDIA EGL has no device-enumeration platform;
    #    the compositor must use GBM, and the modifier GBM path BAD_ALLOCs.
    #    Preload the no-modifier shim (as kmscube does) so GBM surface creation
    #    succeeds. greetd.environment covers the greeter (cosmic-greeter ->
    #    cosmic-comp); sessionVariables covers the logged-in user session.
    systemd.services.greetd.environment.LD_PRELOAD = cosmicPreload;
    environment.sessionVariables.LD_PRELOAD = cosmicPreload;

    # 4. cosmic-comp runs as the cosmic-greeter user (uid 998), but the L4T GPU
    #    device nodes come up root:root 0600 (the BYO-kernel guest lacks
    #    jetpack's GPU udev rules), so NvRm/EGL init fails
    #    (NvRmMemMgrInit/NvRmGpuLibOpen error 196626). Grant the video group
    #    (the graphical session user is in it) read/write on nvmap + the nvhost
    #    GPU nodes. (kmscube worked only because it ran as root.)
    # 5. seat0 gets TWO master-of-seat DRM devices -- card0 (nvdisplay, the
    #    panel) AND the connector-less host1x tegra-drm -- and logind then fails
    #    to hand cosmic-comp DRM master ("Unable to become drm master"). Drop the
    #    host1x DRM nodes from seat0 so only card0 remains the seat's master.
    services.udev.extraRules = ''
      KERNEL=="nvmap", GROUP="video", MODE="0660"
      KERNEL=="nvhost-*", GROUP="video", MODE="0660"
      KERNEL=="nvgpu*", GROUP="video", MODE="0660"
      ENV{DEVNAME}=="/dev/nvgpu/*", GROUP="video", MODE="0660"
      SUBSYSTEM=="drm", DEVPATH=="*/66010000.host1x/*", ENV{ID_SEAT}="seat-unused"
    '';

    # Remaining input/TPM/audio specialisation belongs to the later full-desktop
    # work.
  };
}
