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
stdenv.mkDerivation (finalAttrs: {
  pname = "gala";
  version = "0.1.30.1";

  nativeBuildInputs = [ unzip ];

  buildInputs = [ unzip ];

  # See meta.platforms section for supported platforms
  # TODO: use pname and version when the url is fixed
  src =
    if stdenv.isAarch64 then
      fetchurl {
        url = "https://vedenemo.dev/files/gala/dev.scpp.saca.gala-0.1.30.1-arm64.zip";
        sha256 = "1c1ka8nlxr3ws1faixp1hxxg5i622pqr9mwrxqpqnq6d8hhqva80";
      }
    else
      fetchurl {
        url = "https://vedenemo.dev/files/gala/dev.scpp.saca.gala-0.1.30.1-amd64.zip";
        sha256 = "1dhsgqqfmvlxlvlw36vzwmmmf3113nn8is3c2didwqgx845zgkd4";
      };

  phases = "unpackPhase fixupPhase";
  targetPath = "$out/gala";
  intLibPath = "$out/gala/swiftshader";

  unpackPhase = ''
    mkdir -p ${finalAttrs.targetPath}
    unzip $src -d ${finalAttrs.targetPath}
  '';

  rpath = lib.concatStringsSep ":" [
    libPath
    finalAttrs.targetPath
    finalAttrs.intLibPath
  ];

  fixupPhase = ''
    patchelf \
      --set-interpreter "${dynamic-linker}" \
      --set-rpath "${finalAttrs.rpath}" \
      ${finalAttrs.targetPath}/dev.scpp.saca.gala

    mkdir -p $out/bin
    ln -s $out/gala/dev.scpp.saca.gala $out/bin/gala
  '';

  meta = {
    description = "Google Android look-alike";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
