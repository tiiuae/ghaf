# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  debug ? false,
  shmSlots,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation {
  name = "memsocket";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "ea446dfe3be66004867b6b369950eb16dc04c421";
    sha256 = "sha256-qxrDHxM2z/bIVsTuNx45zZOjp4+BLheWrvco946OMQM=";
  };

  CFLAGS = "-O2 -DSHM_SLOTS=" + (toString shmSlots) + (if debug then " -DDEBUG_ON" else "");
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
