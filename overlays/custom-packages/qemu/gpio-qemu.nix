# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ./overlays/custom-packages/qemu/default.nix

{
  final,
  prev,
}: let
  pkgs = prev.pkgs;

  qemu_version = prev.qemu_kvm.version;
  qemu_major = final.lib.versions.major qemu_version;
  qemu_minor = final.lib.versions.minor qemu_version;

  qemuGpioPatch = ./gpio-passthrough-qemu-9_0.patch;  # this patch is for qemu 9.0.2 but will work for 9.0.1
in
  # qemu_kvm = prev.qemu_kvm.overrideAttrs ( oldAttrs: rec {
  prev.qemu_kvm.overrideAttrs (
    _final: prev:
    {
      patches = (prev.patches or []) ++ [ qemuGpioPatch ];

      /*
      buildInputs = with pkgs; [
        git util-linux pkg-config autoconf autogen automake flex bison meson ninja cmake json_c gcc gnumake libtool valgrind python3 
        glib dbus pixman zlib bzip2 lzo libgpiod snappy curl libssh libcap libepoxy nettle attr systemd liburing 
        makeWrapper mktemp libdrm wayland-protocols SDL2 gtk3 gnutls 
        libslirp libselinux alsa-lib alsa-oss pulseaudio pipewire acpica-tools pam_p11 pam_u2f vte 
        libibumad libnfs libseccomp libxkbcommon libcacard libusb1 libaio libcap_ng libtasn1 libgcrypt keyutils canokey-qemu 
        fuse3 libbpf capstone fdtools vde2 texinfo spice virglrenderer multipath-tools ncurses sealcurses lzfse gsasl xgboost 
        libvncserver cmocka basez SDL2 SDL2_image ceph gsasl xdp-tools fdtools dtc 
      ];*/

      buildInputs = with pkgs; [
        autoconf autogen automake gnumake libtool flex bison meson ninja glib SDL2 gtk3 vde2 vte dbus curl libssh libepoxy libaio liburing zlib bzip2 lzo ncurses 
      ];

      configurePhase = ''
        ./configure \
        --target-list=aarch64-softmmu \
        --enable-sdl \
        --enable-gtk \
        --enable-opengl \
        --enable-vnc \
        --enable-vnc-jpeg \
        --disable-docs \
        --prefix=$out \
        --enable-vde \
        --enable-vhost-net \
        --enable-vhost-user
      '';

      installPhase = ''
        make install
        ln -s $out/bin/qemu-system-aarch64 $out/bin/qemu-passthrough
      '';

      meta = {
        description = "QEMU with passthrough modifications for Ghaf";
        homepage = "https://github.com/KimGSandstrom/qemu-passthrough";
        # license = lib.licenses.apache2;
      };
    }
    # Add additional custom configurations for `qemu_gpio` if needed
  )
