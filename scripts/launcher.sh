#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- Locate runtime root with nix/store ---
resolve_runtime_root() {
  if [[ -n ${RUNTIME_ROOT:-} ]]; then
    echo "$RUNTIME_ROOT"
    return 0
  fi
  # Script directory (works when the launcher is inside the runtime root)
  local d
  d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -d "$d/nix/store" ]]; then
    echo "$d"
    return 0
  fi
  return 1
}

# Parse args
DEBUG="false"
RUNTIME_ROOT=""
ARCHIVE_MODE="false"
FLASH_ARGS=()
usage() {
  cat <<EOF
Usage: $0 [--runtime-root=PATH | --runtime-root PATH] [--debug] [--help] [FLASH_OPTION ...]

Mount the runtime's nix/store and run flash-ghaf-host. Options after the
launcher options are passed unchanged to flash-ghaf-host.

  --runtime-root PATH  Directory containing nix/store (or set RUNTIME_ROOT)
  --debug              Print launcher diagnostics
  -h, --help           Show this help
EOF
}
while (($#)); do
  case "$1" in
  --runtime-root=*)
    RUNTIME_ROOT="${1#*=}"
    shift
    ;;
  --runtime-root)
    (($# >= 2)) || {
      echo "--runtime-root requires a path" >&2
      exit 2
    }
    RUNTIME_ROOT="$2"
    shift 2
    ;;
  --debug)
    DEBUG="true"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    FLASH_ARGS+=("$@")
    break
    ;;
  *)
    FLASH_ARGS+=("$1")
    shift
    ;;
  esac
done
if [[ -z $RUNTIME_ROOT ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  shopt -s nullglob
  archives=("$SCRIPT_DIR"/*.tar "$SCRIPT_DIR"/*.tar.gz "$SCRIPT_DIR"/*.tgz)
  shopt -u nullglob
  if ((${#archives[@]} == 1)); then
    candidate="${archives[0]}"
    if [[ -f $candidate ]]; then
      RUNTIME_ROOT="$(mktemp -d)"
      ARCHIVE_MODE="true"
      case "$candidate" in
      *.tar.gz | *.tgz) tar -xzf "$candidate" -C "$RUNTIME_ROOT" ;;
      *) tar -xf "$candidate" -C "$RUNTIME_ROOT" ;;
      esac
    fi
  elif ((${#archives[@]} > 1)); then
    echo "Multiple runtime archives beside launcher; use --runtime-root after extracting one." >&2
    exit 1
  fi
fi
if [[ -z $RUNTIME_ROOT ]]; then
  RUNTIME_ROOT="$(resolve_runtime_root)" || {
    echo "Could not find a runtime root containing nix/store." >&2
    echo "Usage: $0 --runtime-root=/path/to/runtime [--debug] [FLASH_OPTION ...]" >&2
    exit 1
  }
fi
if [[ $ARCHIVE_MODE == "true" ]]; then
  cleanup_runtime() {
    chmod -R u+w -- "$RUNTIME_ROOT" 2>/dev/null || true
    rm -rf -- "$RUNTIME_ROOT"
  }
  trap cleanup_runtime EXIT
fi
[[ -d "$RUNTIME_ROOT/nix/store" ]] || {
  echo "Runtime store not found: $RUNTIME_ROOT/nix/store" >&2
  exit 1
}

# Determine exact binary path; prefer recorded file if present
if [[ -f "$RUNTIME_ROOT/.flash-bin-path" ]]; then
  FLASH_PATH_ABS="$(tr -d '\r\n' <"$RUNTIME_ROOT/.flash-bin-path")"
else
  shopt -s nullglob
  matches=("$RUNTIME_ROOT"/nix/store/*-flash-ghaf-host/bin/flash-ghaf-host)
  shopt -u nullglob
  [[ ${#matches[@]} -gt 0 ]] || {
    echo "flash-ghaf-host not found in runtime root"
    exit 1
  }
  FLASH_PATH_ABS="/nix/store/$(basename "$(dirname "${matches[0]}")")/bin/flash-ghaf-host"
fi
[[ -x "$RUNTIME_ROOT${FLASH_PATH_ABS}" ]] || {
  echo "Missing: $RUNTIME_ROOT${FLASH_PATH_ABS}"
  exit 1
}

command -v sudo >/dev/null 2>&1 || {
  echo "sudo required"
  exit 1
}

echo "→ Creating private mount namespace and running $FLASH_PATH_ABS"

# If unshare exists, prefer private mount namespace; otherwise, global mount fallback.
if command -v unshare >/dev/null 2>&1; then
  # Build inner script (runs as root in a private mount ns)
  read -r -d '' INNER <<'EOSH' || true
set -euo pipefail

# Inputs: RUNTIME_ROOT, FLASH_PATH_ABS, DEBUG, HOST_PATH
FLASH_ARGS=("$@")

# 1) Create /nix and bind the USB's nix (only in this mount ns)
mkdir -p /nix
mount --bind "$RUNTIME_ROOT/nix" /nix || { echo "ERROR: bind-mount failed"; exit 1; }
# 1a) Ensure exec on the bind mount even if USB is 'noexec'
mount -o remount,bind,exec /nix 2>/dev/null || mount -o remount,exec /nix 2>/dev/null || true

# 2) PATH: prefer all /nix/store/*/bin, then fall back to host PATH
PATH_BUILT=""
for d in /nix/store/*/bin; do
  [ -d "$d" ] && PATH_BUILT="$d:$PATH_BUILT"
done
export PATH="${PATH_BUILT}${HOST_PATH:+:$HOST_PATH}"

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "DEBUG: RUNTIME_ROOT=$RUNTIME_ROOT"
  echo "DEBUG: FLASH_PATH_ABS=$FLASH_PATH_ABS"
  echo "DEBUG: PATH=$PATH"
fi
# 3) Decide how to exec flash-ghaf-host:
#    - If ELF: exec directly
#    - If script: use shebang interpreter if present; else fallback to same interpreter by basename from PATH

# Detect if script via shebang magic
magic="$(dd if="$FLASH_PATH_ABS" bs=2 count=1 status=none 2>/dev/null || true)"
if [[ "$magic" == "#!"* ]]; then
  IFS= read -r firstline < "$FLASH_PATH_ABS" || true
  interp="${firstline#\#!}"     # remove "#!"
  set -- $interp                # split shebang into interpreter + args
  interpreter="${1:-}"; shift || true
  if [[ -n "$interpreter" && -x "$interpreter" ]]; then
    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Using shebang interpreter: $interpreter $*"
    exec "$interpreter" "$FLASH_PATH_ABS" "${FLASH_ARGS[@]}" "$@"
  else
    base="${interpreter##*/}"
    if [[ -n "$base" ]] && command -v "$base" >/dev/null 2>&1; then
      [[ "$DEBUG" == "true" ]] && echo "DEBUG: Shebang interp not on /nix; using host PATH: $base $*"
      exec "$base" "$FLASH_PATH_ABS" "${FLASH_ARGS[@]}" "$@"
    else
      if command -v bash >/dev/null 2>&1; then
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Falling back to 'bash' from host PATH"
        exec bash "$FLASH_PATH_ABS" "${FLASH_ARGS[@]}"
      fi
      echo "ERROR: Cannot resolve interpreter for shebang: '$interp'" >&2
      exit 127
    fi
  fi
else
  [[ "$DEBUG" == "true" ]] && echo "DEBUG: Detected ELF; exec directly"
  exec "$FLASH_PATH_ABS" "${FLASH_ARGS[@]}"
fi
EOSH

  # Run inner script with environment propagated
  sudo --preserve-env=RUNTIME_ROOT,FLASH_PATH_ABS,DEBUG \
    env RUNTIME_ROOT="$RUNTIME_ROOT" FLASH_PATH_ABS="$FLASH_PATH_ABS" DEBUG="$DEBUG" HOST_PATH="$PATH" \
    unshare -m --propagation private bash -c "$INNER" launcher-inner "${FLASH_ARGS[@]}"
else
  # Fallback: global bind mount (safe on non-Nix hosts; avoid on NixOS workstations)
  echo "WARN: 'unshare' not found; using global /nix bind mount (requires sudo)."
  sudo mkdir -p /nix
  sudo mount --bind "$RUNTIME_ROOT/nix" /nix
  sudo mount -o remount,bind,exec /nix 2>/dev/null || sudo mount -o remount,exec /nix 2>/dev/null || true
  trap 'sudo umount /nix || true' EXIT

  # Prefer /nix/store/*/bin tools, then host PATH
  PATH_BUILT=""
  for d in /nix/store/*/bin; do
    [ -d "$d" ] && PATH_BUILT="$d:$PATH_BUILT"
  done
  export PATH="${PATH_BUILT}:$PATH"

  "$FLASH_PATH_ABS" "${FLASH_ARGS[@]}"
fi
