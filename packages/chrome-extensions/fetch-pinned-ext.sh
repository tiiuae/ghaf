#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# This script is very hacky:
# Essentially, we navigate to the crx4chrome extension page
# for the given ext ID, then navigate to its' history page(s), check the
# first 10 pages for the necessary version, once found fetch
# the crx4chrome native ID for the given ext version
# Finally, we can navigate to the crx4chrome page with the native ID
# and get the Google server link to the pinned version blob

# Disable shellcheck for unassigned $out
# shellcheck disable=SC2154
set -euo pipefail
export PATH="$curlMinimal/bin:$gnugrep/bin:$coreutils/bin:$tinyxxd/bin"

EXTENSION_ID="$1"
TARGET_VERSION="$2"
BASE_URL="https://www.crx4chrome.com"

verify_crx() {
  if [ ! -f "$out" ] || [ ! -s "$out" ]; then
    echo "Extension ($EXTENSION_ID) download failed - file is empty. Ensure destination URL is correct." >&2
    exit 1
  fi
  # Check CRX header
  if ! tinyxxd -l 16 "$out" | grep -qiE '(Cr24|CrX3)'; then
    echo "Extension ($EXTENSION_ID) download failed - invalid CRX file (missing Cr24/CrX3 header)." >&2
    exit 1
  fi
  exit 0
}

fetch() {
  curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" "$1"
}

echo "Fetching extension page for $EXTENSION_ID..."
EXT_HTML=$(fetch "$BASE_URL/extensions/$EXTENSION_ID/")
LATEST_CRX_ID=$(echo "$EXT_HTML" | grep -oP 'href="/history/\K[0-9]+(?=/)' | head -1)
echo "crx4chrome ID: $LATEST_CRX_ID"
[[ -z $LATEST_CRX_ID ]] && echo "Error: could not find crx4chrome ID" && exit 1

PAGE=1
while [[ $PAGE -le 10 ]]; do
  if [[ $PAGE -eq 1 ]]; then
    HISTORY_URL="$BASE_URL/history/$LATEST_CRX_ID/"
  else
    HISTORY_URL="$BASE_URL/history/$LATEST_CRX_ID/$PAGE/"
  fi

  echo "Fetching history page $PAGE: $HISTORY_URL"
  HISTORY_HTML=$(fetch "$HISTORY_URL")

  NEEDED_CRX_ID=$(echo "$HISTORY_HTML" |
    grep "v${TARGET_VERSION}[^0-9]" |
    grep -oP 'href="/crx/\K[0-9]+(?=/)' |
    tail -1 || true)
  echo "Version CRX ID for $TARGET_VERSION: ${VERSION_CRX_ID:-not found on this page}"

  if [[ -n $NEEDED_CRX_ID ]]; then
    echo "Found version $TARGET_VERSION at /crx/$NEEDED_CRX_ID/"
    raw=$(fetch "$BASE_URL/crx/$NEEDED_CRX_ID/" |
      grep -i "download crx from web store server" |
      grep -oP 'https[^"]+googleusercontent[^"]+\.crx')
    BLOB_URL=$(printf '%b' "${raw//%/\\x}")
    echo "Decoded blob URL: $BLOB_URL"
    echo "Downloading CRX to $out..."
    curl -L -o "$out" "$BLOB_URL" && echo "Done"
    verify_crx
  fi

  # No more pages to navigate to
  if ! echo "$HISTORY_HTML" | grep -qP 'href="/history/'"$LATEST_CRX_ID"'/'$((PAGE + 1))'/"'; then
    break
  fi

  ((PAGE++))
done

echo "Error: reached page limit without finding version $TARGET_VERSION"
exit 1
