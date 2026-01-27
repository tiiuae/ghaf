{
  # SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
  # SPDX-License-Identifier: Apache-2.0
  coreutils,
  e2fsprogs,
  gawk,
  mtools,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "extract-signed-orin-artifacts";
  runtimeInputs = [
    coreutils
    e2fsprogs
    gawk
    mtools
    zstd
  ];
  text = builtins.readFile ../../../modules/secureboot/extract-signed-orin-artifacts.sh;
  meta = {
    description = "Helper that extracts signed Jetson Orin artifacts from a sd-image build result";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
