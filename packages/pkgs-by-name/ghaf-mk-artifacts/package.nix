# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  openssl,
  python3,
  sbsigntool,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-mk-artifacts";
  runtimeInputs = [
    openssl
    sbsigntool
  ];
  text = ''
    exec ${python3}/bin/python ${../../../modules/partitioning/mk-manifest.py} "$@"
  '';
  meta = {
    description = "Generate and sign Ghaf update artifacts and manifest";
    mainProgram = "ghaf-mk-artifacts";
  };
}
