# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  coreutils,
  jsign,
  vault,
  sbsigntool
}:
writeShellApplication {
  name = "sign-disk-image";
  runtimeInputs = [
    coreutils
    jsign
    vault
    sbsigntool
  ];
  text = builtins.readFile ./sign_disk_image.sh;
  meta = {
    description = "Secure Boot signing script for plain disk image";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
