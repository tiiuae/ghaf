#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  echo "Usage: ghaf-sign-x86-image --key-dir DIR --input IMAGE_DIR --output DIR" >&2
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
[[ $EUID -eq 0 ]] || {
  echo "ghaf-sign-x86-image must run as root to mount the image ESP" >&2
  exit 1
}
for required in db.key db.crt PK.crt KEK.crt update.pub PK.auth KEK.auth db.auth; do
  [[ -s $key_dir/$required ]] || {
    echo "Missing $key_dir/$required" >&2
    exit 1
  }
done
[[ -s $input/public-trust.json ]] || {
  echo "Missing $input/public-trust.json; the image does not expose its evaluated trust inventory" >&2
  exit 1
}
[[ $(jq -er '.external == true' "$input/public-trust.json") == true ]] || {
  echo "Refusing to sign an x86 image evaluated with CI-only public trust; rebuild with an external secure-ab-build-config input" >&2
  exit 1
}
for public_file in PK.crt KEK.crt db.crt update.pub; do
  expected=$(jq -er --arg name "$public_file" '.publicTrustDigests[$name]' "$input/public-trust.json")
  actual=$(sha256sum "$key_dir/$public_file")
  actual=${actual%% *}
  [[ $actual == "$expected" ]] || {
    echo "Public trust mismatch for $public_file; rebuild with a secure-ab-build-config exported from this exact key directory" >&2
    exit 1
  }
done
[[ -s $input/ghaf-image.raw.zst ]] || {
  echo "Missing $input/ghaf-image.raw.zst" >&2
  exit 1
}
[[ ! -e $output ]] || {
  echo "Refusing to overwrite $output" >&2
  exit 1
}

key_pub=$(mktemp)
cert_pub=$(mktemp)
work=$(mktemp -d)
loop=""
mounted=false
cleanup() {
  if $mounted; then
    umount "$work/esp" || true
  fi
  if [[ -n $loop ]]; then
    losetup -d "$loop" || true
  fi
  rm -f "$key_pub" "$cert_pub"
  rm -rf "$work"
}
trap cleanup EXIT

openssl pkey -in "$key_dir/db.key" -pubout -out "$key_pub"
openssl x509 -in "$key_dir/db.crt" -pubkey -noout -out "$cert_pub"
cmp -s "$key_pub" "$cert_pub" || {
  echo "db.key does not match db.crt" >&2
  exit 1
}

zstd -d "$input/ghaf-image.raw.zst" -o "$work/ghaf-image.raw"
loop=$(losetup --find --show --partscan "$work/ghaf-image.raw")
udevadm settle
esp=$(
  lsblk -nrpo NAME,PARTTYPE "$loop" |
    awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" { print $1; exit }'
)
[[ -n $esp ]] || {
  echo "No EFI system partition found in the image" >&2
  exit 1
}
mkdir "$work/esp"
mount -t vfat "$esp" "$work/esp"
mounted=true

sign_one() {
  local file=$1 signed="$work/signed.efi"
  sbsign --key "$key_dir/db.key" --cert "$key_dir/db.crt" \
    --output "$signed" "$file"
  sbverify --cert "$key_dir/db.crt" "$signed" >/dev/null
  install -m 0644 "$signed" "$file"
}

for loader in \
  "$work/esp/EFI/systemd/systemd-bootx64.efi" \
  "$work/esp/EFI/BOOT/BOOTX64.EFI"; do
  [[ -f $loader ]] || {
    echo "Missing required x86 EFI loader: ${loader#"$work/esp/"}" >&2
    exit 1
  }
  sign_one "$loader"
done

mapfile -d '' ukis < <(find "$work/esp/EFI/Linux" -maxdepth 1 -type f -iname '*.efi' -print0 2>/dev/null)
((${#ukis[@]} > 0)) || {
  echo "No Type-2 UKI found under EFI/Linux; refusing an incomplete Secure Boot image" >&2
  exit 1
}
for uki in "${ukis[@]}"; do
  sign_one "$uki"
done

if find "$work/esp/loader/entries" -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null | grep -q .; then
  echo "Type-1 boot entries remain in loader/entries; refusing an image whose initrd/cmdline are not UKI-bound" >&2
  exit 1
fi

sync -f "$work/esp"
umount "$work/esp"
mounted=false
losetup -d "$loop"
loop=""

mkdir -m 0700 "$output"
bmaptool create "$work/ghaf-image.raw" -o "$output/ghaf-image.bmap"
zstd -T0 --compress "$work/ghaf-image.raw" -o "$output/ghaf-image.raw.zst"
install -m 0644 \
  "$key_dir/PK.auth" \
  "$key_dir/KEK.auth" \
  "$key_dir/db.auth" \
  "$key_dir/db.crt" \
  "$output/"
install -m 0644 "$input/public-trust.json" "$output/"
echo "Signed x86 image and matching enrollment payload written to $output"
