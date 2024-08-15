# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  debug,
  vms,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation {
  name = "memsocket";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "4eef1a7e1f6993a9ba0ef1aa066145c410e2eec6";
    sha256 = "sha256-uaKBtb+bD42RK/Z96dhMrGxNXg+ZV/6iW52ouNQ+QSY=";
  };

  CFLAGS =
    "-O2 -DVM_COUNT="
    + (toString vms)
    + (
      if debug
      then " -DDEBUG_ON"
      else ""
    );
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
