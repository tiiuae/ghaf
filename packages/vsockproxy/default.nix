# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  fetchFromGitHub,
  meson,
  ninja,
  stdenv,
}:
stdenv.mkDerivation {
  name = "vsockproxy";

  depsBuildBuild = [
    meson
    ninja
  ];

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "vsockproxy";
    rev = "860038bd8a97f85f89dda30c703bf816a6ac7409";
    sha256 = "sha256-U+gwIEstKiV3o69Bf+Y6a7VFlmD75pIv465z8xcWmN8=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install ./vsockproxy $out/bin/vsockproxy

    runHook postInstall
  '';

  meta = {
    description = "vsockproxy";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
