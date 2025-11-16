# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  makeWrapper,
  efibootmgr,
  python3,
}:

stdenv.mkDerivation {
  pname = "efiboot-clean";
  version = "0";
  src = ./efiboot-clean.py;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m0755 $src $out/bin/efiboot-clean
    wrapProgram $out/bin/efiboot-clean --prefix PATH : ${lib.makeBinPath [ efibootmgr ]}
    runHook postInstall
  '';
  meta.mainProgram = "efiboot-clean";
}
