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
    sha256 = "sha256-+NTEVg1+Xwd05tEMvmFBCkCx2rplXk7rlXuIt6XuQf4=";
  };

  buildInputs = [pkgs.makeWrapper pkgs.ruby_2_7];

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
