#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

DEFAULT_ATTR=".#nvidia-jetson-orin-nx-debug-from-x86_64-flash-runtime"
DESTINATION="${1:-}"
INSTALLABLE="${2:-$DEFAULT_ATTR}"

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  cat <<'EOF'
Usage: port.sh [DESTINATION] [FLAKE_INSTALLABLE]

Build a Nix-defined portable flash runtime and optionally copy its archive and
launcher to a local directory. The Nix output contains the exact flasher
closure and its matching launcher; this script does not assemble store paths.

Examples:
  ./scripts/port.sh
  ./scripts/port.sh /mnt/usb
  ./scripts/port.sh /mnt/usb .#nvidia-jetson-orin-nx-debug-from-x86_64-flash-runtime
EOF
  exit 0
fi

if [[ $INSTALLABLE == \#* ]]; then
  INSTALLABLE=".$INSTALLABLE"
fi

printf '→ Building %s\n' "$INSTALLABLE"
OUTPUT="$(nix build "$INSTALLABLE" --no-link --print-out-paths)"
[[ -f "$OUTPUT/flash-runtime.tar.gz" && -x "$OUTPUT/launcher.sh" ]] || {
  echo "Expected flash-runtime.tar.gz and launcher.sh in Nix output: $OUTPUT" >&2
  exit 1
}

if [[ -n $DESTINATION ]]; then
  mkdir -p -- "$DESTINATION"
  install -m 644 "$OUTPUT/flash-runtime.tar.gz" "$DESTINATION/flash-runtime.tar.gz"
  install -m 755 "$OUTPUT/launcher.sh" "$DESTINATION/launcher.sh"
  printf 'Runtime artifact copied to %s\n' "$DESTINATION"
else
  printf 'Runtime output: %s\n' "$OUTPUT"
fi
