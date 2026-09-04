# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-update-manifest";
  runtimeInputs = [ python3 ];
  text = ''
    exec python3 ${./ghaf-update-manifest.py} "$@"
  '';
  meta = {
    description = "Generate and rehash Ghaf secure update manifests";
    mainProgram = "ghaf-update-manifest";
  };
}
