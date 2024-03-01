# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bash,
  imagePath,
  substituteAll,
}:
substituteAll {
  dir = "bin";
  isExecutable = true;

  pname = "ghaf-installer";
  src = ./ghaf-installer.sh;
  inherit imagePath;

  buildInputs = [
    bash
  ];

  postInstall = ''
    patchShebangs $out/bin/ghaf-installer.sh
  '';
}
