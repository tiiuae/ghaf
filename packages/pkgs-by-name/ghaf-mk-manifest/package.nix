# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  runCommand,
  python3,
  python3Packages,
}:
runCommand "ghaf-mk-manifest"
  {
    src = ./mk-manifest.py;
    nativeBuildInputs = [
      python3
      python3Packages.mypy
    ];
  }
  ''
    mypy "$src"

    install -Dm755 "$src" "$out/bin/ghaf-mk-manifest"
    patchShebangs "$out/bin/ghaf-mk-manifest"
  ''
