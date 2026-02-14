# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  writeShellApplication,
  zstd,
  gawk,
  pv,
}:
writeShellApplication {
  name = "ghafdd.sh";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    gawk
    pv
  ];
  text = builtins.readFile ./ghafdd.sh;
  meta = {
    description = "Fast flashing script for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
