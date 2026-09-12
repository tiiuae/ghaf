#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  echo "Usage: ghaf-dev-keygen --output DIR" >&2
  exit 2
}

output=""
while (($#)); do
  case "$1" in
  --output)
    output="${2:-}"
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -n $output ]] || usage

umask 077
mkdir -p "$output/recovery-passphrases"
chmod 0700 "$output" "$output/recovery-passphrases"
for file in PK.key PK.crt KEK.key KEK.crt db.key db.crt update.key update.pub update.pub.der; do
  if [[ -e "$output/$file" ]]; then
    echo "Refusing to overwrite $output/$file" >&2
    exit 1
  fi
done

for name in PK KEK db; do
  openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
    -subj "/CN=Ghaf development $name/" -days 3650 \
    -keyout "$output/$name.key" -out "$output/$name.crt"
done

openssl genpkey -algorithm ED25519 -out "$output/update.key"
openssl pkey -in "$output/update.key" -pubout -outform DER -out "$output/update.pub.der"
tail -c 32 "$output/update.pub.der" >"$output/update.pub"
rm "$output/update.pub.der"
[[ $(stat -c%s "$output/update.pub") -eq 32 ]]
chmod 0600 "$output"/*.key "$output/update.pub"
echo "Development trust directory created at $output"
echo "Private keys must remain outside Git and the Nix store."
