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
    rev = "851e995b4c24a776f78d56310010e4e29456921c";
    sha256 = "sha256-fyawskwts4OIBshGDeh5ANeBCEm3h5AyHCyhwfxgP14=";
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
