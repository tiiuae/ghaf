#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ghaf-initialize-verity-lvm --update-dir DIR \
  --root-size-mib MIB --verity-size-mib MIB \
  [--device BLOCK_DEVICE] [--vg-name NAME] [--create-inactive-slots] \
  [--swap-size-mib MIB] [--persist-size-mib MIB] [--print-plan]

Creates a Ghaf A/B LVM layout on an already-open block device. Without
--create-inactive-slots, only the populated A-slot is created. --print-plan
validates the payload and prints JSON without modifying a device.
EOF
  exit 2
}

device=""
update_dir=""
root_size_mib=""
verity_size_mib=""
vg_name="pool"
create_inactive_slots=false
swap_size_mib=0
persist_size_mib=0
print_plan=false

while (($#)); do
  case "$1" in
  --device)
    device="${2:-}"
    shift 2
    ;;
  --update-dir)
    update_dir="${2:-}"
    shift 2
    ;;
  --root-size-mib)
    root_size_mib="${2:-}"
    shift 2
    ;;
  --verity-size-mib)
    verity_size_mib="${2:-}"
    shift 2
    ;;
  --vg-name)
    vg_name="${2:-}"
    shift 2
    ;;
  --create-inactive-slots)
    create_inactive_slots=true
    shift
    ;;
  --swap-size-mib)
    swap_size_mib="${2:-}"
    shift 2
    ;;
  --persist-size-mib)
    persist_size_mib="${2:-}"
    shift 2
    ;;
  --print-plan)
    print_plan=true
    shift
    ;;
  *) usage ;;
  esac
done

[[ -d $update_dir ]] || usage
for value in "$root_size_mib" "$verity_size_mib"; do
  [[ $value =~ ^[1-9][0-9]*$ ]] || usage
done
for value in "$swap_size_mib" "$persist_size_mib"; do
  [[ $value =~ ^[0-9]+$ ]] || usage
done
[[ $vg_name =~ ^[A-Za-z0-9_+.-]+$ ]] || usage

mapfile -d '' manifests < <(find -H "$update_dir" -maxdepth 1 -type f -name '*.manifest' -print0)
if ((${#manifests[@]} != 1)); then
  echo "Expected exactly one update manifest in $update_dir" >&2
  exit 1
fi
manifest=${manifests[0]}

jq -e '
  .manifest_version == 2
  and (.root.file | type == "string" and length > 0)
  and (.verity.file | type == "string" and length > 0)
  and (.root.unpacked_size | type == "number" and floor == . and . > 0)
  and (.verity.unpacked_size | type == "number" and floor == . and . > 0)
' "$manifest" >/dev/null

root_file=$(jq -er '.root.file' "$manifest")
verity_file=$(jq -er '.verity.file' "$manifest")
for file in "$root_file" "$verity_file"; do
  [[ $file == "$(basename -- "$file")" && $file != . && $file != .. ]] || {
    echo "Unsafe update artifact path: $file" >&2
    exit 1
  }
  [[ -f "$update_dir/$file" ]] || {
    echo "Missing update artifact: $update_dir/$file" >&2
    exit 1
  }
done

root_bytes=$(jq -er '.root.unpacked_size' "$manifest")
verity_bytes=$(jq -er '.verity.unpacked_size' "$manifest")
required_root_mib=$(((root_bytes + 1048575) / 1048576))
required_verity_mib=$(((verity_bytes + 1048575) / 1048576))
if ((required_root_mib > root_size_mib)); then
  echo "Root artifact needs $required_root_mib MiB but root slot capacity is $root_size_mib MiB" >&2
  exit 1
fi
if ((required_verity_mib > verity_size_mib)); then
  echo "Verity artifact needs $required_verity_mib MiB but verity slot capacity is $verity_size_mib MiB" >&2
  exit 1
fi

lv_suffix=${root_file#ghaf_root_}
lv_suffix=${lv_suffix%.raw.zst}
if [[ -z $lv_suffix || $lv_suffix == "$root_file" || ! $lv_suffix =~ ^[A-Za-z0-9_.+-]+$ ]]; then
  echo "Cannot derive a safe LVM slot suffix from $root_file" >&2
  exit 1
fi
if [[ $verity_file != "ghaf_verity_$lv_suffix.raw.zst" ]]; then
  echo "Root and verity artifact slot names do not match" >&2
  exit 1
fi

slot_copies=1
$create_inactive_slots && slot_copies=2
minimum_pv_size_mib=$((\
  slot_copies * (root_size_mib + verity_size_mib) + swap_size_mib + persist_size_mib + 64))

if $print_plan; then
  jq -n \
    --arg root_file "$root_file" \
    --arg verity_file "$verity_file" \
    --arg lv_suffix "$lv_suffix" \
    --argjson root_size_mib "$root_size_mib" \
    --argjson verity_size_mib "$verity_size_mib" \
    --argjson minimum_pv_size_mib "$minimum_pv_size_mib" \
    '{root_file: $root_file, verity_file: $verity_file, lv_suffix: $lv_suffix,
      root_size_mib: $root_size_mib, verity_size_mib: $verity_size_mib,
      minimum_pv_size_mib: $minimum_pv_size_mib}'
  exit 0
fi

[[ -b $device ]] || {
  echo "--device must identify an already-open block device" >&2
  exit 1
}
if findmnt --noheadings --source "$device" >/dev/null; then
  echo "Refusing to initialize mounted device $device" >&2
  exit 1
fi

lvm_config='devices { use_devicesfile=0 } activation { udev_sync=0 udev_rules=0 }'
lvm_args=(--devices "$device" --config "$lvm_config")
build_vg="ghaf_init_$$_$RANDOM"
vg_active=false
cleanup() {
  if $vg_active; then
    vgchange "${lvm_args[@]}" --activate n "$build_vg" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

pvcreate "${lvm_args[@]}" "$device"
vgcreate "${lvm_args[@]}" "$build_vg" "$device"
vg_active=true

create_lv() {
  local name=$1 size_mib=$2
  lvcreate "${lvm_args[@]}" --yes --zero n --wipesignatures n \
    --size "${size_mib}M" --name "$name" "$build_vg"
}

create_lv "root_$lv_suffix" "$root_size_mib"
create_lv "verity_$lv_suffix" "$verity_size_mib"
zstd --decompress "$update_dir/$root_file" --stdout |
  dd of="/dev/$build_vg/root_$lv_suffix" bs=4M conv=notrunc status=progress
zstd --decompress "$update_dir/$verity_file" --stdout |
  dd of="/dev/$build_vg/verity_$lv_suffix" bs=4M conv=notrunc status=progress

if $create_inactive_slots; then
  create_lv root_empty "$root_size_mib"
  create_lv verity_empty "$verity_size_mib"
fi
if ((swap_size_mib > 0)); then
  create_lv swap "$swap_size_mib"
  mkswap --label swap "/dev/$build_vg/swap"
fi
if ((persist_size_mib > 0)); then
  create_lv persist "$persist_size_mib"
  mkfs.btrfs --force --label persist "/dev/$build_vg/persist"
fi

sync
vgchange "${lvm_args[@]}" --activate n "$build_vg"
vg_active=false
vgrename "${lvm_args[@]}" "$build_vg" "$vg_name"
echo "Initialized Ghaf verity LVM volume group $vg_name on $device"
