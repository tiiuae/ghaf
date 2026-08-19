# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  openssl,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-dev-keygen";
  runtimeInputs = [
    coreutils
    openssl
  ];
  text = builtins.readFile ./ghaf-dev-keygen.sh;
  meta.description = "Generate local Ghaf development UEFI and update signing keys";
}
