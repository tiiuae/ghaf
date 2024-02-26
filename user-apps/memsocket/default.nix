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
    rev = "7ba1b1465aa6f733eb5849e33ffd25232026d5d2";
    sha256 = "sha256-jPr7GBa+zFKYBV4atfjRyNURHEarmxfaoOPnsRYogb8=";
  };

  nativeBuildInputs = with pkgs; [ gcc gnumake ];

  CFLAGS = "-O2 -DVM_COUNT=" + (toString vms)  + (if debug then " -DDEBUG_ON" else "");
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
