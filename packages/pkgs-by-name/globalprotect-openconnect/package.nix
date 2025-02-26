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
}
