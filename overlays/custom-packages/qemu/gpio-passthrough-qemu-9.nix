# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# this derivaton builds Qemu 9.0.x that works for GPIO Passthrough 
# with the acpi-gpio-passthrough-qemu-9.0.patch (which is applied in this derivation)

{ final, prev }:
let
  pkgs = prev.pkgs;
  # builtins = import <nixpkgs> (import <builtins> {});
  # builtins = (import <builtins> {});

  qemu_version = prev.qemu_kvm.version;
  qemu_major = final.lib.versions.major qemu_version;
  qemu_minor = final.lib.versions.minor qemu_version;

  qemuGpioPatch = ./gpio-passthrough-qemu-9.patch; # the patch is for v9.0.2

in
  prev.qemu_kvm.overrideAttrs (
  _final: prev:
  (final.lib.optionalAttrs (qemu_major == "9") {
    patches = builtins.trace "Patching Qemu for GPIO passthrough"
      prev.patches ++ [ qemuGpioPatch ];

    /*
    buildInputs = with pkgs; 
      prev.buildInputs ++
      [
      # git util-linux pkg-config autoconf autogen automake flex bison meson ninja cmake json_c gcc gnumake libtool valgrind python3
      # makeWrapper mktemp wayland-protocols
      glib dbus pixman zlib bzip2 lzo libgpiod snappy curl libssh libcap libepoxy nettle attr systemd liburing 
      libdrm  SDL2 gtk3 gnutls 
      libslirp libselinux alsa-lib alsa-oss pulseaudio pipewire acpica-tools pam_p11 pam_u2f vte 
      libibumad libnfs libseccomp libxkbcommon libcacard libusb1 libaio libcap_ng libtasn1 libgcrypt keyutils canokey-qemu 
      fuse3 libbpf capstone fdtools vde2 texinfo spice virglrenderer multipath-tools ncurses sealcurses lzfse gsasl xgboost 
      libvncserver cmocka basez SDL2 SDL2_image ceph gsasl xdp-tools fdtools dtc 
      ];
    */
    buildInputs = with pkgs; 
      prev.buildInputs ++
      [
        glib gtk3 gtk3-x11 ncurses nettle curl
        SDL2 SDL2_image vte libxkbcommon
        virglrenderer rutabaga_gfx pixman
        vte libvncserver gtk-vnc fuse fuse3 libnfs
        keyutils rng-tools snappy attr cmocka sysprof libsysprof-capture
        libepoxy lzfse libcacard libibumad libseccomp libtpms
        usbredir libusb1 libusbp libaio libssh libgcrypt libcap libslirp libbpf 
        gusb libevdev libevdevplus libevdevc libudev-zero libudev0-shim liburing
        iconv libdwg libdrm dbus libgpiod libtasn1 gsasl cyrus_sasl
        rdma-core libndctl libseccomp capstone multipath-tools dtc libselinux
        perl spice spice-autorandr spice-gtk spice-protocol spice-up spice-vdagent
      ];

    configureFlags = 
      prev.configureFlags ++
      [
        "--target-list=aarch64-softmmu"
        "--disable-strip"
        "--disable-docs"
        "--disable-spice"
        "--enable-tools"
        "--localstatedir=/var"
        "--sysconfdir=/etc"
        # "--cross-prefix="
        "--enable-guest-agent"
        "--enable-numa"
        "--enable-seccomp"
        "--enable-smartcard"
        "--enable-usb-redir"
        "--enable-linux-aio"
        "--enable-tpm"
        "--enable-libiscsi"
        "--enable-linux-io-uring"
        "--enable-canokey"
        "--enable-capstone"
        "--enable-virtfs"

        "--enable-gtk"
        "--enable-opengl"
        "--enable-virglrenderer"
        "--enable-sdl"
        "--enable-vnc"
        "--enable-vnc-jpeg"
        "--enable-vde"
        "--enable-vhost-net"
        "--enable-vhost-user"
        # "--prefix=$out"
      ];

    /*
    installPhase = ''
      make install
      ln -s $out/bin/qemu-system-aarch64 $out/bin/qemu-passthrough
    '';
    */

    meta = {
      description = "QEMU with passthrough modifications for Ghaf";
      homepage = "https://github.com/KimGSandstrom/qemu-passthrough";
      # license = lib.licenses.apache2;
    };

  })
    # Add additional custom configurations for `qemu_gpio` if needed
  )
