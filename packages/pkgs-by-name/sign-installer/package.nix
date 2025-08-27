# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  coreutils,
  squashfsTools,
  zstd,
  sign-disk-image
}:
writeShellApplication {
  name = "sign-installer";
  runtimeInputs = [
    coreutils
    squashfsTools
    zstd
    sign-disk-image
  ];
  text = builtins.readFile ./sign_installer_iso.sh;
  checkPhase = "true";
  meta = {
    description = "Secure Boot signing script for ISO installer";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
