# Copyright 2024 NixOS Contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  fetchurl,
  cmake,
  libsForQt5,
  openconnect,
}:

libsForQt5.mkDerivation rec {
  pname = "globalprotect-openconnect";
  version = "1.4.9";

  src = fetchurl {
    url = "https://github.com/yuezk/GlobalProtect-openconnect/releases/download/v${version}/globalprotect-openconnect-${version}.tar.gz";
    hash = "sha256-vhvVKESLbqHx3XumxbIWOXIreDkW3yONDMXMHxhjsvk=";
  };

  nativeBuildInputs = [
    cmake
    libsForQt5.wrapQtAppsHook
  ];

  buildInputs = [
    openconnect
    libsForQt5.qtwebsockets
    libsForQt5.qtwebengine
    libsForQt5.qtkeychain
  ];

  patchPhase = ''
    substituteInPlace GPService/gpservice.h \
      --replace /usr/local/bin/openconnect ${openconnect}/bin/openconnect;
    substituteInPlace GPService/CMakeLists.txt \
      --replace /etc/gpservice $out/etc/gpservice;
  '';

  meta = {
    description = "GlobalProtect VPN client (GUI) for Linux based on OpenConnect that supports SAML auth mode";
    homepage = "https://github.com/yuezk/GlobalProtect-openconnect";
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };

  # TODO:
  # > Error: detected mismatched Qt dependencies:
  # >     /nix/store/9m61affyj0zjpl8i0mpd8yyw70gw43fm-qtbase-5.15.16-dev
  # >     /nix/store/ihbsfncbkp72ap1y5dqj13aj112jm6va-qtbase-5.15.16-dev
  # broken = stdenv.buildPlatform != stdenv.hostPlatform;
}
