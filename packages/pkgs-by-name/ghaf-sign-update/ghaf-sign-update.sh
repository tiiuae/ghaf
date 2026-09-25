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
for required in db.key db.crt update.key update.pub; do
  [[ -s "$key_dir/$required" ]] || {
    echo "Missing $key_dir/$required" >&2
    exit 1
  }
done

trust_check=$(mktemp -d)
cleanup() { rm -rf "$trust_check"; }
trap cleanup EXIT
openssl pkey -in "$key_dir/db.key" -pubout -outform DER -out "$trust_check/db-key.der"
openssl x509 -in "$key_dir/db.crt" -pubkey -noout -out "$trust_check/db-cert.pem"
openssl pkey -pubin -in "$trust_check/db-cert.pem" -outform DER -out "$trust_check/db-cert.der"
cmp -s "$trust_check/db-key.der" "$trust_check/db-cert.der" || {
  echo "db.key does not match db.crt" >&2
  exit 1
}
openssl pkey -in "$key_dir/update.key" -pubout -outform DER -out "$trust_check/update-key.der"
tail -c 32 "$trust_check/update-key.der" >"$trust_check/update-key.raw"
if [[ $(stat -c%s "$key_dir/update.pub") -ne 32 ]] ||
  ! cmp -s "$trust_check/update-key.raw" "$key_dir/update.pub"; then
  echo "update.key does not match update.pub" >&2
  exit 1
fi
source_dir=$(cd "$(dirname "$input")" && pwd)
# Keep the validated manifest stable while copying and signing its artifacts.
mkdir "$trust_check/manifest"
cp "$input" "$trust_check/manifest/"
input="$trust_check/manifest/$(basename "$input")"
ghaf-update-manifest validate --manifest "$input"

mkdir -p "$output"
manifest="$output/$(basename "$input")"
cp "$input" "$manifest"

mkdir "$trust_check/kernel"
for kind in root verity kernel; do
  file=$(jq -er ".$kind.file" "$input")
  copy="$output/$file"
  if [[ $kind == kernel ]]; then copy="$trust_check/kernel/$file"; fi
  cp "$source_dir/$file" "$copy"
  # Verify the copy so the checked bytes are the ones published or signed.
  [[ $(sha256sum "$copy" | cut -d' ' -f1) == "$(jq -er ".$kind.sha256" "$input")" ]] || {
    echo "$file does not match the sha256 recorded in the input manifest" >&2
    exit 1
  }
done

kernel=$(jq -er '.kernel.file' "$input")
sbsign --key "$key_dir/db.key" --cert "$key_dir/db.crt" \
  --output "$output/$kernel" "$trust_check/kernel/$kernel"
sbverify --cert "$key_dir/db.crt" "$output/$kernel" >/dev/null

# Reuse the manifest generator's validation and hashing implementation after
# UKI signing changes the kernel bytes.
ghaf-update-manifest rehash --manifest "$manifest"

openssl pkeyutl -sign -rawin -inkey "$key_dir/update.key" \
  -in "$manifest" -out "$manifest.sig"
[[ $(stat -c%s "$manifest.sig") -eq 64 ]]
echo "Signed update written to $output"
