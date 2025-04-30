# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  debug ? false,
  shmSlots ? null,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation {
  name = "memsocket";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "ab8a3c9f7dd891a6048968460686e5a2ebcd3b62";
    sha256 = "sha256-UbKhYTdonLq5pDcSnYa9897d6omq438Zsnhr0qj1CTI=";
  };

  CFLAGS = "-O2 -DSHM_SLOTS=" + (toString shmSlots) + (if debug then " -DDEBUG_ON" else "");
  sourceRoot = "source/app";

  installPhase = ''
    mkdir -p $out/bin
    install ./memsocket $out/bin/memsocket
  '';

  meta = {
    description = "memsocket";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
