# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  lib,
  ...
}:
stdenv.mkDerivation {
  name = "vsockproxy";

  nativeBuildInputs = with pkgs; [meson ninja];

  src = pkgs.fetchFromGitHub {
    owner = "tiiuae";
    repo = "vsockproxy";
    rev = "aad625f9a27ce4c68d9996c65ece8477ace37534";
    sha256 = "sha256-3WgpDlF8oIdlgwkvl7TPR6WAh+qk0mowzuYiPY0rwaU=";
  };

  installPhase = ''
    mkdir -p $out/bin
    install ./vsockproxy $out/bin/vsockproxy
  '';

  meta = with lib; {
    description = "vsockproxy";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
