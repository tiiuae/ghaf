#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  echo "Usage: ghaf-sign-update --key-dir DIR --input MANIFEST --output DIR" >&2
  exit 2
}

key_dir="" input="" output=""
while (($#)); do
  case "$1" in
  --key-dir)
    key_dir="${2:-}"
    shift 2
    ;;
  --input)
    input="${2:-}"
    shift 2
    ;;
  --output)
    output="${2:-}"
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -n $key_dir && -n $input && -n $output ]] || usage
for required in db.key db.crt update.key; do
  [[ -s "$key_dir/$required" ]] || {
    echo "Missing $key_dir/$required" >&2
    exit 1
  }
done
[[ $(jq -er '
  .manifest_version == 2
  and (.system | type == "string" and length > 0)
  and (.target | type == "string" and length > 0)
  and (.generation | type == "number" and floor == . and . > 0)
  and (.root_verity_hash | type == "string" and test("^[0-9a-fA-F]{64}$"))
' "$input") == true ]]

source_dir=$(cd "$(dirname "$input")" && pwd)
mkdir -p "$output"
manifest="$output/$(basename "$input")"
cp "$input" "$manifest"

for kind in root verity; do
  file=$(jq -er ".$kind.file" "$manifest")
  [[ $file == "$(basename -- "$file")" ]] || {
    echo "Unsafe artifact path: $file" >&2
    exit 1
  }
  jq -e --arg kind "$kind" '.[$kind].unpacked_size | type == "number" and floor == . and . > 0' \
    "$manifest" >/dev/null
  cp "$source_dir/$file" "$output/$file"
done

kernel=$(jq -er '.kernel.file' "$manifest")
[[ $kernel == "$(basename -- "$kernel")" ]] || {
  echo "Unsafe artifact path: $kernel" >&2
  exit 1
}
sbsign --key "$key_dir/db.key" --cert "$key_dir/db.crt" \
  --output "$output/$kernel" "$source_dir/$kernel"

# Reuse the manifest generator's validation and hashing implementation after
# UKI signing changes the kernel bytes.
ghaf-update-manifest rehash --manifest "$manifest"

openssl pkeyutl -sign -rawin -inkey "$key_dir/update.key" \
  -in "$manifest" -out "$manifest.sig"
[[ $(stat -c%s "$manifest.sig") -eq 64 ]]
echo "Signed update written to $output"
