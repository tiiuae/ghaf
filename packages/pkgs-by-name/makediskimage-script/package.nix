# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  writeShellApplication,
  zstd,
  gawk,
  pv,
  gptfdisk,
  gnused,
  gnugrep,
}:
writeShellApplication {
  name = "makediskimage.sh";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    gawk
    pv
    gptfdisk
    gnused
    gnugrep
  ];
  text = builtins.readFile ./makediskimage.sh;
  meta = {
    description = "esp and root image merger for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
