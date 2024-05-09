# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  ...
}:
stdenv.mkDerivation {
  name = "memtest";

  src = pkgs.fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "67eff363116f21f2090bc56c807c9cb3bfd1699d";
    sha256 = "sha256-5G3brw/yO7xj/n/JZdY3wMD6fN+U4LRUCcf9IAeh3kA=";
  };

  nativeBuildInputs = with pkgs; [gcc gnumake];

  CFLAGS = "-O2";
  prePatch = ''
    cd app/test
  '';

  installPhase = ''
    mkdir -p $out/bin
    install ./memtest $out/bin/memtest
  '';

  meta = with lib; {
    description = "memtest";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
