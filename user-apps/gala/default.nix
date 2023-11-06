# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  pkgs,
  gtk3,
  atk,
  glib,
  pango,
  gdk-pixbuf,
  cairo,
  freetype,
  fontconfig,
  dbus,
  libXi,
  libXcursor,
  libXdamage,
  libXrandr,
  libXcomposite,
  libXext,
  libXfixes,
  libxcb,
  libXrender,
  libX11,
  libXtst,
  libXScrnSaver,
  nss,
  nspr,
  alsa-lib,
  cups,
  expat,
  udev,
  libpulseaudio,
  at-spi2-atk,
  at-spi2-core,
  libxshmfence,
  libdrm,
  libxkbcommon,
  mesa,
  unzip,
  wayland,
}: let
  dynamic-linker = stdenv.cc.bintools.dynamicLinker;

  libPath = lib.makeLibraryPath [
    stdenv.cc.cc
    gtk3
    atk
    glib
    pango
    gdk-pixbuf
    cairo
    freetype
    fontconfig
    dbus
    libXi
    libXcursor
    libXdamage
    libXrandr
    libXcomposite
    libXext
    libXfixes
    libxcb
    libXrender
    libX11
    libXtst
    libXScrnSaver
    nss
    nspr
    alsa-lib
    cups
    expat
    udev
    libpulseaudio
    at-spi2-atk
    at-spi2-core
    libxshmfence
    libdrm
    libxkbcommon
    mesa
    wayland
  ];
in
  stdenv.mkDerivation rec {
    name = "gala";

    nativeBuildInputs = [unzip];

    buildInputs = [unzip];

    # See meta.platforms section for supported platforms
    src =
      if stdenv.isAarch64
      then
        pkgs.fetchurl {
          url = "https://vedenemo.dev/files/6b27cfd7-ca66-481c-9fe5-1fac851fe7e7-gala-electron-test-arm64.zip";
          sha256 = "1z611zr56nm5j96vg5b1vqn1307na2w80wrqd2rnzi4v583zs5z0";
        }
      else
        pkgs.fetchurl {
          url = "https://vedenemo.dev/files/6b27cfd7-ca66-481c-9fe5-1fac851fe7e7-gala-electron-test.zip";
          sha256 = "1kgfarnjg0cs1gh3zrsgrh18dg165n99m3bh0qlz9cqv80375x22";
        };

    phases = "unpackPhase fixupPhase";
    targetPath = "$out/gala";
    intLibPath = "$out/gala/swiftshader";

    unpackPhase = ''
      mkdir -p ${targetPath}
      unzip $src -d ${targetPath}
    '';

    rpath = lib.concatStringsSep ":" [
      libPath
      targetPath
      intLibPath
    ];

    fixupPhase = ''
      patchelf \
        --set-interpreter "${dynamic-linker}" \
        --set-rpath "${rpath}" \
        ${targetPath}/dev.scpp.saca.gala

      mkdir -p $out/bin
      ln -s $out/gala/dev.scpp.saca.gala $out/bin/gala
    '';

    meta = with lib; {
      description = "Google Android look-alike";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  }
