# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  jq,
  openssl,
  python3,
  sbsigntool,
  writeShellApplication,
  writeShellScriptBin,
}:
let
  manifestTool = writeShellScriptBin "ghaf-update-manifest" ''
    exec ${python3}/bin/python ${../../../modules/partitioning/mk-manifest.py} "$@"
  '';
in
writeShellApplication {
  name = "ghaf-sign-update";
  runtimeInputs = [
    coreutils
    jq
    openssl
    sbsigntool
    manifestTool
  ];
  text = builtins.readFile ./ghaf-sign-update.sh;
  meta.description = "Sign a Ghaf update UKI and detached manifest outside the Nix store";
}
