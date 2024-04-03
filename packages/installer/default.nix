# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenvNoCC,
  makeWrapper,
  diskoInstall,
  targetName,
  ghafSource,
  diskName,
}: let
  name = "ghaf-installer";
in
  stdenvNoCC.mkDerivation {
    inherit name;
    src = ./.;
    nativeBuildInputs = [
      makeWrapper
    ];
    installPhase = ''
      mkdir -p $out/bin
      cp ${name}.sh $out/bin/${name}.sh
      chmod 755 $out/bin/${name}.sh
      wrapProgram $out/bin/${name}.sh \
        --set GHAF_SOURCE "${ghafSource}" \
        --set TARGET_NAME "${targetName}" \
        --set DISKO_DISK_NAME "${diskName}" \
        --prefix PATH : ${lib.makeBinPath [diskoInstall]}
    '';
  }
