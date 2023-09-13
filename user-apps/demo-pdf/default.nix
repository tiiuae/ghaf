# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  ...
}:
stdenv.mkDerivation {
  name = "demo-pdf";

  src = ./Whitepaper.pdf;
  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out/bin
    cp ${./Whitepaper.pdf} $out/Whitepaper.pdf
    echo "zathura $out/Whitepaper.pdf" > $out/bin/run-zathura
    chmod 755 $out/bin/run-zathura
  '';

  meta = with lib; {
    description = "Demo PDF";
    platforms = [
      "x86_64-linux"
    ];
  };
}
