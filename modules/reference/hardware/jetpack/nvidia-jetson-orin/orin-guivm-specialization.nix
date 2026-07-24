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
  # cosmic-comp needs the no-modifier GBM path (modifier surfaces BAD_ALLOC on
  # this L4T EGL); EGL device-enumeration is handled compositor-side by the
  # cosmic-comp-egl-device-optional patch (overlay above), not a preload.
  cosmicPreload = "${gbm-nomod-shim}/lib/gbm-nomod-shim.so";
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

    # Patch cosmic-comp for two L4T/Tegra NVIDIA KMS limitations: its EGL does
    # not provide usable EGLDevice enumeration, and nvdisplay does not scan out
    # cursor-plane position updates despite accepting them. Use the GBM device
    # node and software-composite the cursor, respectively.
    nixpkgs.overlays = [
      (_final: prev: {
        cosmic-comp = prev.cosmic-comp.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [
            ./cosmic-comp-egl-device-optional.patch
            ./cosmic-comp-nvidia-software-cursor.patch
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

    # FIX (Phase 6 input): logind won't activate cosmic-comp's session on this
    # headless gui-vm (no fbcon -> VT-based handoff can't complete). Use seatd in
    # its documented VT-less mode, which activates the single session without
    # waiting for a VT switch and brokers the DRM/input device fds. Point libseat
    # at seatd and give the greeter/user seat-group access.
    services.seatd.enable = true;
    systemd.services.seatd.environment.SEATD_VTBOUND = "0";
    environment.sessionVariables.LIBSEAT_BACKEND = "seatd";
    users.users.cosmic-greeter.extraGroups = [ "seat" ];
    users.users.ghaf.extraGroups = [
      "seat"
      "video"
    ];

    # The static `ghaf` user authenticates directly through greetd's pam_unix
    # conversation. No earlier PAM module supplies PAM_AUTHTOK in this image, so
    # pam_unix with `use_first_pass` rejects every login without asking greetd
    # for the entered password ("auth could not identify password"). Retain the
    # default `try_first_pass`, but allow pam_unix to prompt when the token is
    # absent.
    security.pam.services.greetd.rules.auth.unix.settings.use_first_pass = lib.mkForce false;

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

    # 3. cosmic-comp used to die on init: Tegra's NVIDIA EGL has no
    #    device-enumeration platform (eglQueryDevicesEXT BAD_ALLOCs), so
    #    EGLDevice matching failed ("Unable to find matching egl device"). Fixed
    #    compositor-side by the cosmic-comp-egl-device-optional patch (overlay
    #    above) which degrades the EGLDevice to Optional and uses GBM. The
    #    modifier GBM path still BAD_ALLOCs, so preload the no-modifier shim (as
    #    kmscube does) so GBM surface creation succeeds. greetd.environment
    #    covers the greeter (cosmic-greeter -> cosmic-comp); sessionVariables
    #    covers the logged-in user session.
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
    # 6. No keyboard/mouse in cosmic. vhotplug passes the USB receiver into the
    #    gui-vm fine (input devices present), but cosmic-comp fails to become the
    #    logind session controller ("Unable to become drm master, assuming
    #    unprivileged mode") and so opens devices DIRECTLY, relying on uaccess
    #    ACLs. card0 carries :uaccess: (display works), but input devices get
    #    only :power-switch: -- no uaccess, no ACL for the greeter uid (998) ->
    #    open() EACCES -> cosmic-comp reads no input. Tag input with uaccess so
    #    logind grants the active-session user an ACL (exactly how card0 works;
    #    confirmed on HW: cosmic-comp then OPENS event0/1/2). NOTE: this is a
    #    permission PREREQUISITE only -- it does not by itself make input work.
    #    Events also require the evdev-only passthrough fix (the USB receiver is
    #    denied from usb-host in the Orin target so it reaches gui-vm via
    #    virtio-input; see targets/nvidia-jetson-orin/flake-module.nix). Single-user
    #    gui-vm appliance, so session-wide input access is acceptable.
    #    NOTE: cosmic-comp is now the privileged session controller via seatd
    #    (SEATD_VTBOUND=0 above), so it opens input through seatd/TakeDevice; this
    #    uaccess tag is a harmless belt-and-suspenders for any direct open.
    #    ponytail: uaccess = active-session user can read all input (keylogger
    #    surface); acceptable for a single-user appliance.
    services.udev.extraRules = ''
      KERNEL=="nvmap", GROUP="video", MODE="0660"
      KERNEL=="nvhost-*", GROUP="video", MODE="0660"
      KERNEL=="nvgpu*", GROUP="video", MODE="0660"
      ENV{DEVNAME}=="/dev/nvgpu/*", GROUP="video", MODE="0660"
      SUBSYSTEM=="drm", DEVPATH=="*/66010000.host1x/*", ENV{ID_SEAT}="seat-unused"
      SUBSYSTEM=="input", ENV{ID_INPUT}=="1", TAG+="uaccess"
    '';

    # Remaining input/TPM/audio specialisation belongs to the later full-desktop
    # work.
  };
}
