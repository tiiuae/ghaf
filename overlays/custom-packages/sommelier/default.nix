# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  final,
  prev,
}:
prev.sommelier.overrideAttrs (_final: prevAttrs: {
  version = "122.0";
  src = prev.fetchzip rec {
    url = "https://chromium.googlesource.com/chromiumos/platform2/+archive/${passthru.rev}/vm_tools/sommelier.tar.gz";
    passthru.rev = "2d4f46c679da7a4e8c447c8cf68c74b80f9de3fe";
    stripRoot = false;
    sha256 = "sha256-LNGA1r2IO3Ekh+dK6HUge001qC2TFvxwjhM0iaY0DbU=";
  };

  nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [final.python3 final.python3.pkgs.jinja2];
  postPatch = ''
    patchShebangs gen-shim.py
  '';
})
