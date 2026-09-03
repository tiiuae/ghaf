#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  echo "Usage: ghaf-secure-ab-config --key-dir DIR --generation N --output DIR" >&2
  exit 2
}

key_dir="" generation="" output=""
while (($#)); do
  case "$1" in
  --key-dir)
    key_dir="${2:-}"
    shift 2
    ;;
  --generation)
    generation="${2:-}"
    shift 2
    ;;
  --output)
    output="${2:-}"
    shift 2
    ;;
  *) usage ;;
  esac
done

[[ -n $key_dir && -n $generation && -n $output ]] || usage
[[ $generation =~ ^[1-9][0-9]*$ ]] || {
  echo "GENERATION must be a positive decimal integer" >&2
  exit 2
}
[[ ! -e $output ]] || {
  echo "Refusing to overwrite $output" >&2
  exit 1
}
for file in PK.crt KEK.crt db.crt update.pub; do
  [[ -s "$key_dir/$file" ]] || {
    echo "Missing $key_dir/$file" >&2
    exit 1
  }
done

mkdir -p "$(dirname "$output")"
staging="$(mktemp -d "${output}.tmp.XXXXXX")"
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT

for file in PK.crt KEK.crt db.crt update.pub; do
  cp -- "$key_dir/$file" "$staging/$file"
done
jq -n --argjson generation "$generation" \
  '{schema_version: 1, trust: "external", generation: $generation}' \
  >"$staging/config.json"
chmod 0444 "$staging"/*
mv -- "$staging" "$output"
trap - EXIT

echo "Public secure A/B build configuration created at $output"
echo "Use it as the secure-ab-build-config flake input; it contains no private keys."
