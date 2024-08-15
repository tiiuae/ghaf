# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  fetchurl,
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
}:
let
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

  nativeBuildInputs = [ unzip ];

  buildInputs = [ unzip ];

  # See meta.platforms section for supported platforms
  src =
    if stdenv.isAarch64 then
      fetchurl {
        url = "https://vedenemo.dev/files/gala/eb56901d-410c-4c09-bbac-9e954a3f16b0-gala-electron-test-0.1.26-arm64.zip";
        sha256 = "16d8g6h22zsnw4kq8nkama5yxp5swn7fj8m197kgm58w3dai3mn7";
      }
    else
      fetchurl {
        url = "https://vedenemo.dev/files/gala/eb56901d-410c-4c09-bbac-9e954a3f16b0-gala-electron-test-0.1.26.zip";
        sha256 = "0chn1rbdvs71mxfdwpld4v2zdg2crrqln9ckscivas48rmg6sj6f";
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
