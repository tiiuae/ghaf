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
    rev = "2c0a4bad482ec2e076aee9a1ce550b3d9891f05e";
    sha256 = "sha256-4cXNdG1k45/mF+yqBsfvfYkRK6N9kgsGeeqGB6mRSj4=";
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
