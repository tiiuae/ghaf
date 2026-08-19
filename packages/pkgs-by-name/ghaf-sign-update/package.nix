# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  jq,
  openssl,
  sbsigntool,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-sign-update";
  runtimeInputs = [
    coreutils
    jq
    openssl
    sbsigntool
  ];
  text = builtins.readFile ./ghaf-sign-update.sh;
  meta.description = "Sign a Ghaf update UKI and detached manifest outside the Nix store";
}
