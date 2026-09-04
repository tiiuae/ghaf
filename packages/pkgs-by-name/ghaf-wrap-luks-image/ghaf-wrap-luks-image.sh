#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ghaf-wrap-luks-image --image FILE --uuid UUID --key-file FILE \
  [--header-size-mib MIB]

Converts a sparse plaintext regular-file image to LUKS2 in place without a
loop device or device-mapper. The result retains sparse plaintext holes and
is extended by the requested LUKS header space.
EOF
  exit 2
}

image=""
luks_uuid=""
key_file=""
header_size_mib=32

while (($#)); do
  case "$1" in
  --image)
    image="${2:-}"
    shift 2
    ;;
  --uuid)
    luks_uuid="${2:-}"
    shift 2
    ;;
  --key-file)
    key_file="${2:-}"
    shift 2
    ;;
  --header-size-mib)
    header_size_mib="${2:-}"
    shift 2
    ;;
  *) usage ;;
  esac
done

[[ -f $image && -f $key_file ]] || usage
[[ $header_size_mib =~ ^[1-9][0-9]*$ ]] || usage
((header_size_mib >= 16)) || {
  echo "LUKS2 conversion needs at least 16 MiB of header space" >&2
  exit 1
}
[[ $luks_uuid =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || usage

image=$(realpath -- "$image")
key_file=$(realpath -- "$key_file")
image_size=$(stat --format=%s "$image")
header_size=$((header_size_mib * 1048576))
image_dir=$(dirname -- "$image")
image_base=$(basename -- "$image")
plain_image=$(mktemp --tmpdir="$image_dir" ".$image_base.plain.XXXXXX")
construction_key=$(mktemp)
complete=false
cleanup() {
  status=$?
  trap - EXIT
  rm -f -- "$construction_key"
  if ! $complete && [[ -f $plain_image ]]; then
    rm -f -- "$image"
    mv -- "$plain_image" "$image"
  else
    rm -f -- "$plain_image"
  fi
  exit "$status"
}
trap cleanup EXIT

mv -- "$image" "$plain_image"
truncate -s "$((image_size + header_size))" "$image"
head -c 32 /dev/urandom | base64 >"$construction_key"

# qemu-img's userspace LUKS writer can skip sparse source ranges. Create a
# LUKS1 header with enough aligned space for LUKS2 first, populate only data
# extents, then convert the header in place. No kernel crypto mapping is used.
mkdir -p /tmp/cryptsetup
cryptsetup luksFormat \
  --batch-mode \
  --type luks1 \
  --align-payload "$((header_size / 512))" \
  --uuid "$luks_uuid" \
  --key-file "$construction_key" \
  "$image"
qemu-img convert \
  --object "secret,id=construction,file=$construction_key" \
  --no-create \
  --target-is-zero \
  --source-format raw \
  --target-image-opts \
  --sparse-size 4k \
  "$plain_image" \
  "driver=luks,key-secret=construction,file.driver=file,file.filename=$image"
cryptsetup convert --type luks2 "$image"
cryptsetup luksAddKey \
  --batch-mode \
  --key-file "$construction_key" \
  "$image" "$key_file"
cryptsetup luksRemoveKey \
  --batch-mode \
  --key-file "$construction_key" \
  "$image"

cryptsetup isLuks --type luks2 "$image"
actual_uuid=$(cryptsetup luksUUID "$image")
if [[ $actual_uuid != "${luks_uuid,,}" ]]; then
  echo "LUKS UUID mismatch: expected $luks_uuid, got $actual_uuid" >&2
  exit 1
fi
actual_offset=$(cryptsetup luksDump --dump-json-metadata "$image" |
  jq -er '.segments."0".offset | tonumber')
if [[ $actual_offset != "$header_size" ]]; then
  echo "LUKS payload offset mismatch: expected $header_size, got $actual_offset" >&2
  exit 1
fi

complete=true
rm -f -- "$plain_image" "$construction_key"
trap - EXIT
