# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  hwinfo,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    hwinfo
  ];
  text = builtins.readFile ./ghaf-installer.sh;
}
