# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# AArch64 specialization of the generic gui-vm desktop.
{ lib, pkgs, ... }:
let
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  cosmicPreload = "${support.gbmNoModifiersShim}/lib/gbm-nomod-shim.so";
in
{
  _file = ./orin-guivm-specialization.nix;

  config = {
    nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

    # Handle unusable EGLDevice enumeration and missed DMA-BUF fence wakeups.
    nixpkgs.overlays = [
      (_final: prev: {
        cosmic-comp = prev.cosmic-comp.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [
            ./cosmic-comp-egl-device-optional.patch
            ./cosmic-comp-tegra-dmabuf-fence-poll.patch
          ];
        });
        mesa-demos = prev.mesa-demos.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [
            ./mesa-demos-wayland-shared-fd-nonblocking.patch
          ];
        });
      })
    ];

    microvm.vcpu = lib.mkForce 4;

    # gpu-screen-recorder is x86_64-only.
    ghaf.graphics.cosmic.screenRecorder.enable = lib.mkForce false;

    # cosmic-greeter 1.1.0 passes an empty password to PAM when unlocking.
    ghaf.graphics.cosmic.idleManagement.enable = lib.mkForce false;

    # COSMIC prepends /dev/dri/ and therefore requires a bare render-node name.
    ghaf.graphics.cosmic.renderDevice = lib.mkForce null;
    systemd.services.greetd.environment.COSMIC_RENDER_DEVICE = "renderD129";
    environment.sessionVariables.COSMIC_RENDER_DEVICE = "renderD129";
    systemd.services.greetd.environment.COSMIC_EGL_RENDER_DEVICE = "renderD129";
    environment.sessionVariables.COSMIC_EGL_RENDER_DEVICE = "renderD129";
    systemd.services.greetd.environment.RUST_LOG = lib.mkForce "error";
    environment.sessionVariables.RUST_LOG = lib.mkForce "error";

    systemd.services.greetd.environment.COSMIC_POLL_DMABUF_FENCES = "1";
    environment.sessionVariables.COSMIC_POLL_DMABUF_FENCES = "1";

    # The guest has no fbcon, so seat activation must not wait for a VT switch.
    services.seatd.enable = true;
    systemd.services.seatd.environment.SEATD_VTBOUND = "0";
    environment.sessionVariables.LIBSEAT_BACKEND = "seatd";

    # Prevent tty1 from also consuming evdev-delivered keystrokes.
    systemd.services.greetd.serviceConfig.ExecStartPre = [
      "${pkgs.kbd}/bin/kbd_mode -f -d -C /dev/tty1"
    ];
    systemd.services.greetd.serviceConfig.ExecStopPost = [
      "${pkgs.kbd}/bin/kbd_mode -f -u -C /dev/tty1"
    ];
    users.users.cosmic-greeter.extraGroups = [ "seat" ];
    users.users.ghaf.extraGroups = [
      "seat"
      "video"
      # GIVC credentials under /run/givc are root:users 0750.
      "users"
    ];

    # Let pam_unix prompt when cosmic-greeter has no existing token.
    security.pam.services.cosmic-greeter.rules.auth.unix.settings.use_first_pass = lib.mkForce false;

    # The interactive tty1 provisioner would block greetd on this fbcon-less guest.
    ghaf.services.user-provisioning.enable = lib.mkForce false;

    systemd.services.greetd.environment.LD_PRELOAD = cosmicPreload;
    environment.sessionVariables.LD_PRELOAD = cosmicPreload;

    # Expose GPU nodes to the video group and keep connector-less host1x off seat0.
    services.udev.extraRules = ''
      KERNEL=="nvmap", GROUP="video", MODE="0660"
      KERNEL=="nvhost-*", GROUP="video", MODE="0660"
      KERNEL=="nvgpu*", GROUP="video", MODE="0660"
      ENV{DEVNAME}=="/dev/nvgpu/*", GROUP="video", MODE="0660"
      SUBSYSTEM=="drm", DEVPATH=="*/66010000.host1x/*", ENV{ID_SEAT}="seat-unused"
      SUBSYSTEM=="input", ENV{ID_INPUT}=="1", TAG+="uaccess"
    '';
  };
}
