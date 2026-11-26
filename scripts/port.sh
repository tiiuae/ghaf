#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# -----------------------------
# Config / Defaults
# -----------------------------
DEFAULT_DESTINATION="/run/media/emrah/4a6d542b-dd34-4843-b25b-22644ea41060"
DEFAULT_APP_ATTR="#nvidia-jetson-orin-nx-debug-from-x86_64-flash-qspi"

# Set LAUNCHER_URL to fetch a launcher instead of using the local copy.
: "${LAUNCHER_URL_OVERRIDE:=${LAUNCHER_URL:-}}"
: "${LAUNCHER_URL:=https://raw.githubusercontent.com/tiiuae/ghaf/main/scripts/launcher.sh}"
LAUNCHER_NAME="${LAUNCHER_NAME:-launcher.sh}"

# -----------------------------
# Args
# -----------------------------
usage() {
  cat <<'EOF'
Usage: port.sh [--help] [-tar] [DESTINATION] [APP_ATTR]

Build APP_ATTR, copy its runtime closure and launcher to DESTINATION, and
verify the copied flash binary. DESTINATION can be a local directory or an
rsync/SSH destination such as user@host:/path/to/target. Remote destinations
must be writable by the SSH user and have rsync installed.

Arguments:
  -tar         Write a gzip-compressed tar archive; install launcher beside it
  DESTINATION  Local directory or user@host:/absolute/path
               (default: /run/media/emrah/4a6d542b-dd34-4843-b25b-22644ea41060)
  APP_ATTR     Nix flake installable attribute (default: the configured Jetson
               release attribute)

Environment:
  LAUNCHER_URL   Launcher URL to install
  LAUNCHER_NAME  Launcher filename (default: launcher.sh)

Examples:
  port.sh /run/media/$USER/USB
  port.sh emrah@target:/tmp/flash-kit
  port.sh /mnt/usb '#nixosConfigurations.host.config.system.build.toplevel'
  port.sh -tar /mnt/usb/flash-runtime.tar.gz
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
fi

TAR_MODE=0
LOCAL_ARCHIVE=""
if [[ ${1:-} == "-tar" ]]; then
  TAR_MODE=1
  shift
fi
DESTINATION="${1:-$DEFAULT_DESTINATION}"
APP_ATTR="${2:-$DEFAULT_APP_ATTR}"
if [[ $# -gt 2 ]]; then
  echo "Unexpected extra argument(s): ${*:3}" >&2
  usage >&2
  exit 2
fi

# rsync's host:path form identifies an SSH destination. Local paths can
# contain colons after a slash, so only recognize the conventional host:path
# form where the colon precedes any slash.
if [[ $DESTINATION =~ ^([^/:]+@[^/:]+|[^/:]+):(.+)$ ]]; then
  REMOTE_HOST="${BASH_REMATCH[1]}"
  REMOTE_ROOT="${BASH_REMATCH[2]}"
  REMOTE=1
else
  LOCAL_ROOT="$DESTINATION"
  REMOTE=0
fi

if ((TAR_MODE)); then
  if ((REMOTE)); then
    REMOTE_ARCHIVE="$REMOTE_ROOT"
    REMOTE_ROOT="$(dirname -- "$REMOTE_ARCHIVE")"
    case "$REMOTE_ARCHIVE" in
    *.tar.gz | *.tgz) ;;
    *.tar) REMOTE_ARCHIVE="${REMOTE_ARCHIVE%.tar}.tar.gz" ;;
    *) REMOTE_ARCHIVE="$REMOTE_ARCHIVE.tar.gz" ;;
    esac
    REMOTE_LAUNCHER="$REMOTE_ROOT/$LAUNCHER_NAME"
  else
    LOCAL_ARCHIVE="$LOCAL_ROOT"
    LOCAL_ROOT="$(dirname -- "$LOCAL_ARCHIVE")"
    case "$LOCAL_ARCHIVE" in
    *.tar.gz | *.tgz) ;;
    *.tar) LOCAL_ARCHIVE="${LOCAL_ARCHIVE%.tar}.tar.gz" ;;
    *) LOCAL_ARCHIVE="$LOCAL_ARCHIVE.tar.gz" ;;
    esac
    REMOTE_LAUNCHER=""
  fi
  TAR_STAGE="$(mktemp -d)"
  cleanup_tar_stage() {
    [[ -n ${TAR_STAGE:-} && -d $TAR_STAGE ]] || return 0
    chmod -R u+w -- "$TAR_STAGE" 2>/dev/null || true
    rm -rf -- "$TAR_STAGE"
  }
  trap cleanup_tar_stage EXIT
  LOCAL_ROOT="$TAR_STAGE/runtime"
  mkdir -p "$LOCAL_ROOT"
fi

if ((REMOTE)); then
  [[ $REMOTE_ROOT == /* ]] || {
    echo "Remote destination must be an absolute path: $DESTINATION" >&2
    exit 2
  }
else
  if ((! TAR_MODE)); then sudo mkdir -p "$LOCAL_ROOT"; fi
fi

echo "→ DESTINATION : $DESTINATION"
echo "→ APP_ATTR : $APP_ATTR"
if [[ -n $LAUNCHER_URL_OVERRIDE ]]; then
  echo "→ LAUNCHER : $LAUNCHER_URL_OVERRIDE -> $LAUNCHER_NAME"
else
  echo "→ LAUNCHER : local copy -> $LAUNCHER_NAME"
fi

# -----------------------------
# Build the app
# -----------------------------
echo "→ Building $APP_ATTR"
FLASH_OUT="$(nix build ".$APP_ATTR" --print-out-paths)"

# -----------------------------
# Helper: accumulate extra outputs (each line → one array entry)
# -----------------------------
EXTRA_OUTS=()
append_outs() {
  local p="$1"
  while IFS= read -r line; do
    [[ -n $line ]] && EXTRA_OUTS+=("$line")
  done < <(nix build "$p" --print-out-paths)
}

# Optional extras so we *prefer* /nix/store tools if present on the USB
echo "→ Ensuring nixpkgs#bash is included"
append_outs "nixpkgs#bash"
echo "→ Ensuring nixpkgs#coreutils is included (mktemp, dd, head, etc.)"
append_outs "nixpkgs#coreutils"
echo "→ Ensuring nixpkgs#util-linux is included (mount, lsblk, unshare, etc.)"
append_outs "nixpkgs#util-linux"

TARGETS=("$FLASH_OUT" "${EXTRA_OUTS[@]}")

# -----------------------------
# Compute the full runtime closure
# -----------------------------
echo "→ Computing runtime closure"
readarray -t CLOSURE < <(nix-store -qR -- "${TARGETS[@]}")

if [[ ${#CLOSURE[@]} -eq 0 ]]; then
  echo "ERROR: Closure is empty; build likely failed." >&2
  exit 1
fi

# -----------------------------
# Copy the closure reliably
# -----------------------------
echo "→ Copying closure to $DESTINATION with rsync --relative (preserves links/metadata)"
remote_shell_quote() {
  local quoted
  printf -v quoted '%q' "$1"
  printf '%s' "$quoted"
}
if ((REMOTE && ! TAR_MODE)); then
  # Paths are shell-quoted locally before the command is sent over SSH.
  # shellcheck disable=SC2029
  ssh "$REMOTE_HOST" "mkdir -p -- $(remote_shell_quote "$REMOTE_ROOT/nix/store")"
  RSYNC_DEST="$REMOTE_HOST:$REMOTE_ROOT/"
elif ((! TAR_MODE)); then
  sudo mkdir -p "$LOCAL_ROOT/nix/store"
fi

# Remove any previous partial tree for main derivation to avoid stale zero-size files
if ((REMOTE && ! TAR_MODE)); then
  # shellcheck disable=SC2029
  ssh "$REMOTE_HOST" "rm -rf -- $(remote_shell_quote "$REMOTE_ROOT$FLASH_OUT")"
elif ((! TAR_MODE)); then
  sudo rm -rf "$LOCAL_ROOT$FLASH_OUT" || true
fi

for p in "${CLOSURE[@]}"; do
  if [[ -d $p ]]; then
    # Directory: copy contents (trailing slash) and recreate full path
    if ((REMOTE && ! TAR_MODE)); then
      rsync -aH --relative "$p/" "$RSYNC_DEST"
    elif ((TAR_MODE)); then
      rsync -aH --relative "$p/" "$LOCAL_ROOT/"
    else
      sudo rsync -aH --relative "$p/" "$LOCAL_ROOT/"
    fi
  else
    # File: copy as-is, recreating the full path
    if ((REMOTE && ! TAR_MODE)); then
      rsync -aH --relative "$p" "$RSYNC_DEST"
    elif ((TAR_MODE)); then
      rsync -aH --relative "$p" "$LOCAL_ROOT/"
    else
      sudo rsync -aH --relative "$p" "$LOCAL_ROOT/"
    fi
  fi
done
# -----------------------------
# Record the exact binary path for the launcher (NO trailing newline)
# -----------------------------
FLASH_BIN_ABS="/nix/store/$(basename "$FLASH_OUT")/bin/flash-ghaf-host"
if ((REMOTE && ! TAR_MODE)); then
  # shellcheck disable=SC2029
  printf '%s' "$FLASH_BIN_ABS" | ssh "$REMOTE_HOST" "cat > $(remote_shell_quote "$REMOTE_ROOT/.flash-bin-path")"
else
  if ((TAR_MODE)); then
    printf '%s' "$FLASH_BIN_ABS" >"$LOCAL_ROOT/.flash-bin-path"
  else
    printf '%s' "$FLASH_BIN_ABS" | sudo tee "$LOCAL_ROOT/.flash-bin-path" >/dev/null
  fi
fi
if ((TAR_MODE)); then
  echo "→ Recorded flash binary path in staged runtime"
else
  echo "→ Recorded flash binary path at $DESTINATION/.flash-bin-path"
fi

# Verify sizes (source vs destination)
SRC_BIN="$FLASH_OUT/bin/flash-ghaf-host"
if [[ ! -f $SRC_BIN ]]; then
  echo "ERROR: Source binary missing: $SRC_BIN" >&2
  exit 1
fi
SRC_SZ="$(stat -c '%s' "$SRC_BIN")"
if ((REMOTE && ! TAR_MODE)); then
  # shellcheck disable=SC2029
  DST_SZ="$(ssh "$REMOTE_HOST" "stat -c %s -- $(remote_shell_quote "$REMOTE_ROOT$FLASH_BIN_ABS")")"
else
  DST_BIN="$LOCAL_ROOT$FLASH_BIN_ABS"
  if [[ ! -f $DST_BIN ]]; then
    echo "ERROR: Destination binary missing: $DST_BIN" >&2
    exit 1
  fi
  DST_SZ="$(stat -c '%s' "$DST_BIN")"
fi
echo "   Source size: $SRC_SZ bytes"
echo "   Destination size: $DST_SZ bytes"
if [[ $SRC_SZ -eq 0 || $DST_SZ -eq 0 || $SRC_SZ -ne $DST_SZ ]]; then
  echo "ERROR: Size mismatch or zero-byte copy; copy failed. Aborting." >&2
  exit 1
fi

# -----------------------------
# Fetch launcher.sh from GitHub → destination
# -----------------------------
echo "→ Preparing launcher"
TMP_LAUNCHER="$(mktemp)"
fetch_to_file() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    # Fallback: use Nix-provided curl
    local CURL_OUT
    CURL_OUT="$(nix build nixpkgs#curl --print-out-paths)"
    "$CURL_OUT/bin/curl" -fsSL "$url" -o "$dest"
  fi
}
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_LAUNCHER="$SCRIPT_DIR/launcher.sh"
if [[ -n $LAUNCHER_URL_OVERRIDE ]]; then
  if ! fetch_to_file "$LAUNCHER_URL_OVERRIDE" "$TMP_LAUNCHER"; then
    echo "ERROR: Failed to download launcher from $LAUNCHER_URL_OVERRIDE" >&2
    exit 1
  fi
elif [[ -f $LOCAL_LAUNCHER ]]; then
  cp -- "$LOCAL_LAUNCHER" "$TMP_LAUNCHER"
elif ! fetch_to_file "$LAUNCHER_URL" "$TMP_LAUNCHER"; then
  echo "ERROR: Failed to download launcher from $LAUNCHER_URL" >&2
  exit 1
fi

# Install at destination and make executable
if ((REMOTE && ! TAR_MODE)); then
  rsync -a "$TMP_LAUNCHER" "$REMOTE_HOST:$REMOTE_ROOT/$LAUNCHER_NAME"
  # shellcheck disable=SC2029
  ssh "$REMOTE_HOST" "chmod 755 -- $(remote_shell_quote "$REMOTE_ROOT/$LAUNCHER_NAME")"
elif ((! TAR_MODE)); then
  sudo install -Dm755 "$TMP_LAUNCHER" "$LOCAL_ROOT/$LAUNCHER_NAME"
fi
if ((TAR_MODE)); then
  install -Dm755 "$TMP_LAUNCHER" "$LOCAL_ROOT/$LAUNCHER_NAME"
  if [[ $LOCAL_ARCHIVE != "" ]]; then
    mkdir -p "$(dirname -- "$LOCAL_ARCHIVE")"
    tar -C "$LOCAL_ROOT" -czf "$LOCAL_ARCHIVE" .
    install -Dm755 "$TMP_LAUNCHER" "$(dirname -- "$LOCAL_ARCHIVE")/$LAUNCHER_NAME"
  else
    # shellcheck disable=SC2029
    ssh "$REMOTE_HOST" "mkdir -p -- $(remote_shell_quote "$REMOTE_ROOT")"
    # shellcheck disable=SC2029
    tar -C "$LOCAL_ROOT" -czf - . | ssh "$REMOTE_HOST" "cat > $(remote_shell_quote "$REMOTE_ARCHIVE")"
    rsync -a "$TMP_LAUNCHER" "$REMOTE_HOST:$REMOTE_LAUNCHER"
    # shellcheck disable=SC2029
    ssh "$REMOTE_HOST" "chmod 755 -- $(remote_shell_quote "$REMOTE_LAUNCHER")"
  fi
fi
rm -f "$TMP_LAUNCHER"
if ((TAR_MODE)); then
  if ((REMOTE)); then
    echo "→ Placed $LAUNCHER_NAME at $REMOTE_LAUNCHER (executable)"
  else
    echo "→ Placed $LAUNCHER_NAME at $(dirname -- "$LOCAL_ARCHIVE")/$LAUNCHER_NAME (executable)"
  fi
else
  echo "→ Placed $LAUNCHER_NAME at $DESTINATION/$LAUNCHER_NAME (executable)"
fi

# -----------------------------
# Finish
# -----------------------------
echo "Completed."
if ((TAR_MODE)); then
  if ((REMOTE)); then
    echo "   Archive: $DESTINATION"
  else
    echo "   Archive: $LOCAL_ARCHIVE"
  fi
  echo "   Run beside the archive: $LAUNCHER_NAME [flash options...]"
  exit 0
fi
if ((REMOTE)); then
  # shellcheck disable=SC2029
  ssh "$REMOTE_HOST" "du -sh -- $(remote_shell_quote "$REMOTE_ROOT/nix/store")" | awk '{print "Destination store size:", $1}'
else
  sudo du -sh "$LOCAL_ROOT/nix/store" | awk '{print "Destination store size:", $1}'
fi
echo "   Run on target: $LAUNCHER_NAME --runtime-root=/path/to/runtime [flash options...]"
