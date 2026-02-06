# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Development shell for ghaf-hw-test skill
# Provides Python environment with required dependencies
#
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  name = "ghaf-hw-test-shell";

  buildInputs = with pkgs; [
    # Python environment
    (python3.withPackages (
      ps: with ps; [
        pyyaml # Config parsing
        rich # Terminal formatting
        click # CLI framework
      ]
    ))

    # SSH and connectivity
    openssh
    netcat-gnu

    # Utilities
    coreutils
    gnugrep
    gnused
  ];

  shellHook = ''
    export SKILL_DIR="$(dirname "$(readlink -f "$0")")"
    export PYTHONPATH="$SKILL_DIR/lib:$PYTHONPATH"
    echo "ghaf-hw-test skill environment loaded"
  '';
}
