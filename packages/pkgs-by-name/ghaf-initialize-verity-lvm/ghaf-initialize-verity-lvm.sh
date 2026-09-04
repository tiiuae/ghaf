#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ghaf-initialize-verity-lvm --update-dir DIR \
  --root-size-mib MIB --verity-size-mib MIB \
  --image REGULAR_FILE \
  [--vg-name NAME] [--create-inactive-slots] \
  [--swap-size-mib MIB] [--persist-size-mib MIB] [--print-plan]

Creates a Ghaf A/B LVM layout in an existing regular file using the offline
image backend without privileges, loop devices, or device-mapper.
Without --create-inactive-slots, only the populated A-slot is created.
--print-plan validates the payload and prints JSON without modifying a target.
EOF
  exit 2
}

image=""
update_dir=""
root_size_mib=""
verity_size_mib=""
vg_name="pool"
create_inactive_slots=false
swap_size_mib=0
persist_size_mib=0
print_plan=false
image_work_dir=""

while (($#)); do
  case "$1" in
  --image)
    image="${2:-}"
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

[[ -n $image ]] || {
  echo "--image is required unless --print-plan is used" >&2
  exit 1
}

initialize_image() {
  [[ -f $image ]] || {
    echo "--image must identify an existing regular file" >&2
    exit 1
  }
  image=$(realpath -- "$image")
  [[ $image =~ ^[A-Za-z0-9_./:+-]+$ ]] || {
    echo "Image path contains characters unsupported by the LVM configuration syntax" >&2
    exit 1
  }
  local image_size
  image_size=$(stat --format=%s "$image")
  if ((image_size < minimum_pv_size_mib * 1048576)); then
    echo "Image is too small: need at least $minimum_pv_size_mib MiB" >&2
    exit 1
  fi

  local work_dir empty_dev lvm_system_dir offline_lvm lvm_config
  work_dir=$(mktemp -d)
  image_work_dir=$work_dir
  empty_dev="$work_dir/dev"
  lvm_system_dir="$work_dir/lvm"
  mkdir -p "$empty_dev" "$lvm_system_dir/archive" "$lvm_system_dir/backup"
  cleanup_image() {
    if [[ -n $image_work_dir && -d $image_work_dir ]]; then
      rm -r -- "$image_work_dir"
    fi
  }
  trap cleanup_image EXIT

  offline_lvm='@LVM_OFFLINE@'
  lvm_config="devices { loopfiles = [ \"$image\" ] scan = [ \"$empty_dev\" ] use_devicesfile = 0 obtain_device_list_from_udev = 0 sysfs_scan = 0 } global { locking_type = 0 } activation { udev_sync = 0 udev_rules = 0 } backup { backup = 0 archive = 0 }"
  local common_args=(--driverloaded n --nolocking --config "$lvm_config")
  export LVM_SYSTEM_DIR="$lvm_system_dir"
  export LVM_OFFLINE_HOST=ghaf-image
  export LVM_OFFLINE_DESCRIPTION=ghaf-image-builder
  export LVM_OFFLINE_DEVICE_HINT=/dev/ghaf-image
  export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1}"
  export TZ=UTC

  LVM_OFFLINE_UUID_SEED="$vg_name:pv" \
    "$offline_lvm" pvcreate "${common_args[@]}" --yes --force --force \
    --zero y --metadatasize 4M --dataalignment 1M "$image"
  LVM_OFFLINE_UUID_SEED="$vg_name:vg" \
    "$offline_lvm" vgcreate "${common_args[@]}" --yes \
    --physicalextentsize 4M "$vg_name" "$image"

  create_image_lv() {
    local name=$1 size_mib=$2
    LVM_OFFLINE_UUID_SEED="$vg_name:lv:$name" \
      "$offline_lvm" lvcreate "${common_args[@]}" --yes --activate n \
      --zero n --wipesignatures n --size "${size_mib}M" \
      --name "$name" "$vg_name"
  }

  lv_offset_bytes() {
    local name=$1 pe_start extent_size ranges range start
    pe_start=$("$offline_lvm" pvs "${common_args[@]}" --noheadings \
      --units b --nosuffix -o pe_start "$image")
    extent_size=$("$offline_lvm" vgs "${common_args[@]}" --noheadings \
      --units b --nosuffix -o vg_extent_size "$vg_name")
    ranges=$("$offline_lvm" lvs "${common_args[@]}" --noheadings \
      --segments -o seg_pe_ranges "$vg_name/$name")
    pe_start=${pe_start//[[:space:]]/}
    extent_size=${extent_size//[[:space:]]/}
    ranges=${ranges//[[:space:]]/}
    [[ $pe_start =~ ^[0-9]+$ && $extent_size =~ ^[0-9]+$ && $ranges =~ ^.+:[0-9]+-[0-9]+$ ]] || {
      echo "Unexpected LVM extent report for $name: $ranges" >&2
      exit 1
    }
    range=${ranges##*:}
    start=${range%%-*}
    printf '%s\n' "$((pe_start + start * extent_size))"
  }

  write_stream_to_image_lv() {
    local name=$1 size_mib=$2 offset leftover
    offset=$(lv_offset_bytes "$name")
    # Unlike a block device, a regular file has no LV boundary. Bound the
    # stream to the declared slot capacity, then prove that stdin was exhausted.
    dd of="$image" bs=1M count="$size_mib" seek="$offset" \
      iflag=fullblock oflag=seek_bytes conv=notrunc status=none
    leftover=$(dd bs=1 count=1 status=none | wc -c)
    if ((leftover > 0)); then
      echo "Payload for $name exceeds its $size_mib MiB logical volume" >&2
      exit 1
    fi
  }

  write_file_to_image_lv() {
    local name=$1 source=$2 offset
    offset=$(lv_offset_bytes "$name")
    dd if="$source" of="$image" bs=4M seek="$offset" oflag=seek_bytes \
      conv=notrunc,sparse status=none
  }

  create_image_lv "root_$lv_suffix" "$root_size_mib"
  create_image_lv "verity_$lv_suffix" "$verity_size_mib"
  zstd --decompress "$update_dir/$root_file" --stdout |
    write_stream_to_image_lv "root_$lv_suffix" "$root_size_mib"
  zstd --decompress "$update_dir/$verity_file" --stdout |
    write_stream_to_image_lv "verity_$lv_suffix" "$verity_size_mib"

  if $create_inactive_slots; then
    create_image_lv root_empty "$root_size_mib"
    create_image_lv verity_empty "$verity_size_mib"
  fi
  if ((swap_size_mib > 0)); then
    create_image_lv swap "$swap_size_mib"
    truncate -s "${swap_size_mib}M" "$work_dir/swap.img"
    mkswap --label swap "$work_dir/swap.img"
    write_file_to_image_lv swap "$work_dir/swap.img"
  fi
  if ((persist_size_mib > 0)); then
    create_image_lv persist "$persist_size_mib"
    truncate -s "${persist_size_mib}M" "$work_dir/persist.img"
    mkfs.btrfs --force --label persist "$work_dir/persist.img"
    write_file_to_image_lv persist "$work_dir/persist.img"
  fi

  "$offline_lvm" vgck "${common_args[@]}" "$vg_name"
  trap - EXIT
  cleanup_image
  echo "Initialized Ghaf verity LVM volume group $vg_name in $image"
}

initialize_image
