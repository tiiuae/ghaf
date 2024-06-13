# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs}:
pkgs.stdenv.mkDerivation {
  name = "lkp-tests";

  src = pkgs.fetchFromGitHub {
    owner = "intel";
    repo = "lkp-tests";
    rev = "master";
    sha256 = "sha256-tDx2RGLKGMrJ/kbfPurOX2KErndv/TW7u8mdf8Rfl74=";
  };

  buildInputs = [pkgs.ruby_3_3];

  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out
    make install TARGET_DIR_BIN=$out
  '';

  meta = with pkgs.lib; {
    description = "Linux Kernel Performance tests";
    homepage = "https://github.com/intel/lkp-tests";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
