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
    rev = "7ba1b1465aa6f733eb5849e33ffd25232026d5d2";
    sha256 = "sha256-jPr7GBa+zFKYBV4atfjRyNURHEarmxfaoOPnsRYogb8=";
  };

  nativeBuildInputs = with pkgs; [ gcc gnumake ];

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
