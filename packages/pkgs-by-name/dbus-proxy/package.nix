# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  fetchFromGitHub,
  pkgs,
  ...
}:
stdenv.mkDerivation {
  name = "dbus-proxy";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "DBus_proxy";
    rev = "e88fe9d03b08ba4d0b5aecef48efa5d7dfd537e8";
    sha256 = "sha256-qEMwdeD2lj3VGH1DAAhcbu5m6EX9qsd/jd5QtjN8zh4=";
  };

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.glib ];

  sourceRoot = "source";

  installPhase = ''
    mkdir -p $out/bin
    install ./dbus-proxy $out/bin/dbus-proxy
  '';

  meta = {
    description = "DBus proxy";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
