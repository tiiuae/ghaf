# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  efitools,
  openssl,
  util-linux,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-dev-keygen";
  runtimeInputs = [
    coreutils
    efitools
    openssl
    util-linux
  ];
  text = builtins.readFile ./ghaf-dev-keygen.sh;
  meta.description = "Generate local Ghaf development UEFI and update signing keys";
}
