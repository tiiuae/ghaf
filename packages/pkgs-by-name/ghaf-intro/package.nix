# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Introduction Website
# Static HTML site explaining Ghaf's architecture and security model
#
{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "ghaf-intro";
  version = "1.0.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp index.html $out/
    cp -r img $out/
  '';

  meta = {
    description = "Ghaf introduction website - explains architecture and security model";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
