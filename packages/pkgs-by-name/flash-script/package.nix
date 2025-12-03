# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  writeShellApplication,
  zstd,
  pv,
}:
writeShellApplication {
  name = "flash-script";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    pv
  ];
  text = builtins.readFile ./flash.sh;
  meta = {
    description = "Flashing script for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
