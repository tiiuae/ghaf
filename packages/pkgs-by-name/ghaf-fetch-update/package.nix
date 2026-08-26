# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  curl,
  jq,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghaf-fetch-update";
  runtimeInputs = [
    coreutils
    curl
    jq
  ];
  text = ''
    set -euo pipefail

    usage() {
      echo "Usage: ghaf-fetch-update UPDATE_HTTP_ORIGIN GHAF_UPDATE_GENERATION [FETCH_PARENT]" >&2
      exit 2
    }

    [[ $# -ge 2 && $# -le 3 ]] || usage
    UPDATE_HTTP_ORIGIN="$1"
    GHAF_UPDATE_GENERATION="$2"
    FETCH_PARENT="''${3:-/persist/sysupdate}"

    FINAL_DIR="$FETCH_PARENT/http-generation-$GHAF_UPDATE_GENERATION"
    test ! -e "$FINAL_DIR" || {
      echo "Refusing to reuse published fetch directory: $FINAL_DIR" >&2
      exit 1
    }

    FETCH_DIR="$(mktemp -d "$FETCH_PARENT/.http-generation-$GHAF_UPDATE_GENERATION.XXXXXX")"
    chmod 0755 "$FETCH_DIR"

    fetch_file() {
      file="$1"
      case "$file" in
        "" | .* | *[!A-Za-z0-9._-]*)
          echo "Unsafe update file name: $file" >&2
          return 1
          ;;
      esac
      curl --fail --show-error --location \
        --proto '=http' --proto-redir '=http' \
        --retry 3 --retry-all-errors \
        --output "$FETCH_DIR/$file.part" \
        "$UPDATE_HTTP_ORIGIN/$file"
      mv -- "$FETCH_DIR/$file.part" "$FETCH_DIR/$file"
    }

    fetch_file manifest.json
    fetch_file manifest.json.sig

    for kind in root verity kernel; do
      artifact="$(jq -er --arg kind "$kind" '.[$kind].file' "$FETCH_DIR/manifest.json")"
      fetch_file "$artifact"
    done

    touch "$FETCH_DIR/fetch.complete"
    sync "$FETCH_DIR"
    mv -T -- "$FETCH_DIR" "$FINAL_DIR"
    sync "$FETCH_PARENT"
    FETCH_DIR="$FINAL_DIR"

    echo "Fetched update into $FETCH_DIR"
  '';
  meta = {
    description = "Fetch a Ghaf update bundle into /persist/sysupdate";
    mainProgram = "ghaf-fetch-update";
  };
}
