# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  hwinfo,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    zstd
    hwinfo
  ];
  text = builtins.readFile ./ghaf-installer.sh;
}
