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
    # >&2 is load-bearing. ghaf-hw-test runs `nix-shell --run` inside command
    # substitution to read config.yaml, so anything this hook writes to stdout
    # is captured as part of the value. On stdout this banner made every lookup
    # two lines long -- `flash_method` became "...environment loaded\nghaf-flash",
    # which matches no branch of the case statement, so flashing failed with
    # "Unknown flash method" on any host where nix-shell exists.
    echo "ghaf-hw-test skill environment loaded" >&2
  '';
}
