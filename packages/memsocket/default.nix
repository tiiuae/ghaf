# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  debug ? false,
  vms,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation {
  name = "memsocket";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "fd6b8ac051f1c68edc2b3222146d5d9053c81cc6";
    sha256 = "sha256-4FiRZy/HxwANgIAHxUfQo2tl4Dcgpz74SqvuRjqIw8M=";
  };

  CFLAGS = "-O2 -DVM_COUNT=" + (toString vms) + (if debug then " -DDEBUG_ON" else "");
  sourceRoot = "source/app";

  installPhase = ''
    mkdir -p $out/bin
    install ./memsocket $out/bin/memsocket
  '';

  meta = with lib; {
    description = "memsocket";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
