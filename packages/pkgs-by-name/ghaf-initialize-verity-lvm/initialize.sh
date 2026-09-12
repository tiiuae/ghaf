#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  echo "Usage: ghaf-initialize-verity-lvm --manifest FILE --root-size-mib MIB --verity-size-mib MIB [--image BLOCK_DEVICE | --print-plan] [--create-inactive-slots] [--swap-size-mib MIB] [--persist-size-mib MIB] [--luks-uuid UUID --key-file FILE]" >&2
  exit 2
}
manifest="" image="" root_size_mib="" verity_size_mib="" swap_size_mib=0 persist_size_mib=0
luks_uuid="" key_file="" inactive=false print_plan=false
while (($#)); do
  case "$1" in
  --create-inactive-slots)
    inactive=true
    shift
    ;;
  --print-plan)
    print_plan=true
    shift
    ;;
  --manifest | --image | --root-size-mib | --verity-size-mib | --swap-size-mib | --persist-size-mib | --luks-uuid | --key-file)
    (($# >= 2)) || usage
    option=${1#--}
    printf -v "${option//-/_}" '%s' "$2"
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -f $manifest ]] || usage
manifest=$(realpath "$manifest")
ghaf-update-manifest validate --manifest "$manifest"
root_file=$(jq -er '.root.file' "$manifest")
verity_file=$(jq -er '.verity.file' "$manifest")
[[ $root_file =~ ^ghaf_root_([a-zA-Z0-9._-]+)\.raw\.zst$ ]] || usage
suffix=${BASH_REMATCH[1]}
[[ $verity_file == "ghaf_verity_$suffix.raw.zst" && ${#suffix} -lt 121 && $suffix != empty ]] || usage
for size in "$root_size_mib" "$verity_size_mib" "$swap_size_mib" "$persist_size_mib"; do
  # Bound shell arithmetic well below its signed limit, including all six LVs.
  [[ $size =~ ^(0|[1-9][0-9]{0,8})$ ]] || usage
done
((root_size_mib > 0 && verity_size_mib > 0)) || usage
root_bytes=$(jq -er '.root.unpacked_size' "$manifest")
verity_bytes=$(jq -er '.verity.unpacked_size' "$manifest")
# jq performs these comparisons without converting untrusted u64s to shell integers.
jq -e --argjson root "$((root_size_mib * 1048576))" --argjson verity "$((verity_size_mib * 1048576))" \
  '.root.unpacked_size <= $root and .verity.unpacked_size <= $verity' "$manifest" >/dev/null
pairs=1
if $inactive; then pairs=2; fi
minimum_mib=$((64 + pairs * (root_size_mib + verity_size_mib) + swap_size_mib + persist_size_mib))
if $print_plan; then
  jq -n --arg root_file "$root_file" --arg verity_file "$verity_file" --arg lv_suffix "$suffix" \
    --argjson root_size_mib "$root_size_mib" --argjson verity_size_mib "$verity_size_mib" \
    --argjson minimum_pv_size_mib "$minimum_mib" '$ARGS.named'
  exit 0
fi
[[ -b $image && $EUID -eq 0 ]] || usage
[[ -z $luks_uuid && -z $key_file || -n $luks_uuid && -f $key_file ]] || usage
[[ -z $(wipefs --noheadings --output TYPE "$image") ]] || {
  echo "Refusing nonempty disk $image" >&2
  exit 1
}
! vgs pool >/dev/null 2>&1 || {
  echo "VG pool already exists" >&2
  exit 1
}
header_mib=0
if [[ -n $luks_uuid ]]; then header_mib=32; fi
(($(blockdev --getsize64 "$image") >= (minimum_mib + header_mib) * 1048576)) || {
  echo "Image is too small" >&2
  exit 1
}
work=$(mktemp -d "$PWD/verity-payload.XXXXXX")
created=false opened=false
cleanup() {
  status=$?
  trap - EXIT
  if $created; then vgchange -an pool || status=1; fi
  if $opened; then cryptsetup close ghaf-image || status=1; fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
export LVM_SYSTEM_DIR="$work/lvm"
mkdir "$LVM_SYSTEM_DIR"
echo 'devices { use_devicesfile = 0 } activation { udev_sync = 0 udev_rules = 0 }' >"$LVM_SYSTEM_DIR/lvm.conf"
# Validate decompression and exact lengths before creating storage. Scratch files
# are private and immutable during the following copies; LV devices bound writes.
unpack() {
  local source=$1 expected=$2 destination=$3
  # Read one byte beyond the declaration: a count limit alone could silently
  # truncate an oversized stream. pipefail also propagates decoder failures.
  zstd --decompress --stdout --quiet "$source" |
    dd of="$destination" bs=1M iflag=fullblock,count_bytes count="$((expected + 1))" status=none
  [[ $(stat -c%s "$destination") == "$expected" ]] || {
    echo "Unpacked payload length differs from manifest" >&2
    exit 1
  }
}
unpack "$(dirname "$manifest")/$root_file" "$root_bytes" "$work/root"
unpack "$(dirname "$manifest")/$verity_file" "$verity_bytes" "$work/verity"

pv=$image
if [[ -n $luks_uuid ]]; then
  cryptsetup luksFormat --batch-mode --type luks2 --sector-size 512 --offset 65536 \
    --uuid "$luks_uuid" --key-file "$key_file" "$image"
  cryptsetup open --key-file "$key_file" "$image" ghaf-image
  opened=true
  pv=/dev/mapper/ghaf-image
fi
pvcreate "$pv"
vgcreate --physicalextentsize 4M pool "$pv"
created=true
lvcreate --yes --zero n -L "${root_size_mib}M" -n "root_$suffix" pool
lvcreate --yes --zero n -L "${verity_size_mib}M" -n "verity_$suffix" pool
if $inactive; then
  lvcreate --yes --zero n -L "${root_size_mib}M" -n root_empty pool
  lvcreate --yes --zero n -L "${verity_size_mib}M" -n verity_empty pool
fi
vgmknodes pool
dd if="$work/root" of="/dev/pool/root_$suffix" bs=4M conv=fsync status=none
dd if="$work/verity" of="/dev/pool/verity_$suffix" bs=4M conv=fsync status=none
if ((swap_size_mib > 0)); then
  lvcreate --yes --zero n -L "${swap_size_mib}M" -n swap pool
  mkswap --label swap /dev/pool/swap
fi
if ((persist_size_mib > 0)); then
  lvcreate --yes --zero n -L "${persist_size_mib}M" -n persist pool
  mkfs.btrfs --force --label persist /dev/pool/persist
fi
sync
