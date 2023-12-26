# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  debug,
  vms,
  ...
}:
stdenv.mkDerivation {
  inherit debug vms;
  name = "memsocket";

  src = pkgs.fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "67eff363116f21f2090bc56c807c9cb3bfd1699d";
    sha256 = "sha256-5G3brw/yO7xj/n/JZdY3wMD6fN+U4LRUCcf9IAeh3kA=";
  };

  nativeBuildInputs = with pkgs; [gcc gnumake];

  CFLAGS =
    "-O2 -DVM_COUNT="
    + (toString vms)
    + (
      if debug
      then " -DDEBUG_ON"
      else ""
    );
  prePatch = ''
    cd app
  '';

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
