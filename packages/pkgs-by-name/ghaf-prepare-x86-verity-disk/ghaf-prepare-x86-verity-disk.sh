#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ghaf-prepare-x86-verity-disk \
  --update-dir DIR --systemd-boot FILE --trust-inventory FILE \
  --image-size-mib MIB --root-size-mib MIB --verity-size-mib MIB \
  --swap-size-mib MIB --persist-size-mib MIB --boot-timeout VALUE \
  [--output DIR] [--print-plan]

Creates an unsigned x86 GPT/LUKS/LVM secure A/B disk image using regular
files only. It needs no root privileges, loop devices, device mapper, mount,
or VM. --print-plan validates all immutable inputs without creating an image.
EOF
  exit 2
}

update_dir="" systemd_boot="" trust_inventory="" output="" boot_timeout=""
image_size_mib="" root_size_mib="" verity_size_mib="" swap_size_mib="" persist_size_mib=""
print_plan=false
while (($#)); do
  case "$1" in
  --print-plan)
    print_plan=true
    shift
    ;;
  --update-dir | --systemd-boot | --trust-inventory | --output | --boot-timeout | \
    --image-size-mib | --root-size-mib | --verity-size-mib | --swap-size-mib | --persist-size-mib)
    (($# >= 2)) || usage
    # Only the fixed option whitelist above may select a destination variable.
    option=${1#--}
    printf -v "${option//-/_}" '%s' "$2"
    shift 2
    ;;
  *) usage ;;
  esac
done

[[ -d $update_dir && -f $systemd_boot && -f $trust_inventory ]] || usage
for value in "$image_size_mib" "$root_size_mib" "$verity_size_mib"; do
  [[ $value =~ ^[1-9][0-9]*$ ]] || usage
done
for value in "$swap_size_mib" "$persist_size_mib"; do
  [[ $value =~ ^[0-9]+$ ]] || usage
done
[[ $boot_timeout == menu-force || $boot_timeout =~ ^[0-9]+$ ]] || usage

minimum_image_size_mib=$((\
  500 + 2 * root_size_mib + 2 * verity_size_mib + swap_size_mib + persist_size_mib + 4 * 1024))
if ((image_size_mib < minimum_image_size_mib)); then
  echo "Image size is $image_size_mib MiB; at least $minimum_image_size_mib MiB is required" >&2
  exit 1
fi

mapfile -d '' manifests < <(find -H "$update_dir" -maxdepth 1 -type f -name '*.manifest' -print0)
mapfile -d '' ukis < <(find -H "$update_dir" -maxdepth 1 -type f -name '*.efi' -print0)
if ((${#manifests[@]} != 1)); then
  echo "Expected exactly one update manifest in $update_dir" >&2
  exit 1
fi
if ((${#ukis[@]} != 1)); then
  echo "Expected exactly one UKI in $update_dir" >&2
  exit 1
fi
manifest=${manifests[0]}
uki=${ukis[0]}

initialize_lvm() {
  ghaf-initialize-verity-lvm --update-dir "$update_dir" \
    --root-size-mib "$root_size_mib" --verity-size-mib "$verity_size_mib" \
    --create-inactive-slots --swap-size-mib "$swap_size_mib" \
    --persist-size-mib "$persist_size_mib" "$@"
}
lvm_plan=$(initialize_lvm --print-plan)
version=$(jq -er '.version | select(type == "string" and length > 0)' "$manifest")
root_hash=$(jq -er '.root_verity_hash | select(type == "string" and test("^[0-9a-fA-F]{64}$"))' "$manifest")

if $print_plan; then
  jq -n \
    --argjson image_size_mib "$image_size_mib" \
    --argjson minimum_image_size_mib "$minimum_image_size_mib" \
    --arg boot_timeout "$boot_timeout" \
    --argjson lvm "$lvm_plan" \
    '{image_size_mib: $image_size_mib, minimum_image_size_mib: $minimum_image_size_mib,
      boot_timeout: $boot_timeout, lvm: $lvm}'
  exit 0
fi

[[ -n $output ]] || usage
[[ ! -e $output && ! -L $output ]] || {
  echo "Refusing to overwrite $output" >&2
  exit 1
}
output_parent=$(dirname -- "$output")
[[ -d $output_parent ]] || {
  echo "Output parent does not exist: $output_parent" >&2
  exit 1
}
output=$(realpath -m -- "$output")

work=$(mktemp -d)
complete=false
cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$work"
  if ! $complete && [[ -d $output ]]; then
    echo "Image preparation failed; partial output remains at $output" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

mkdir -m 0700 "$output"
raw="$output/ghaf-image.raw"
truncate -s "${image_size_mib}M" "$raw"
last_partition_sector=$(((image_size_mib - 1) * 2048 - 1))
sgdisk --zap-all "$raw"
sgdisk \
  --disk-guid=09A5D6A4-5FA3-4F54-AC76-0B02B636376F \
  --new=1:1MiB:+500MiB \
  --typecode=1:ef00 \
  --change-name=1:ESP \
  --partition-guid=1:7A9F13F8-0A61-46A1-9F5A-216D5FC1A028 \
  --new=2:0:"$last_partition_sector" \
  --typecode=2:8309 \
  --change-name=2:disk-disk1-luks \
  --partition-guid=2:3C05B9C2-6F7C-4B13-ACB7-47C615AAB14A \
  "$raw"

partition_sector() {
  local partition=$1 field=$2 value
  value=$(sgdisk -i "$partition" "$raw" | awk -v field="$field" \
    '$1 " " $2 == field ":" { print $3; exit }')
  [[ $value =~ ^[0-9]+$ ]] || {
    echo "Could not read $field for GPT partition $partition" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

esp_first=$(partition_sector 1 "First sector")
esp_last=$(partition_sector 1 "Last sector")
luks_first=$(partition_sector 2 "First sector")
luks_last=$(partition_sector 2 "Last sector")
esp_size_bytes=$(((esp_last - esp_first + 1) * 512))
luks_size_bytes=$(((luks_last - luks_first + 1) * 512))
luks_header_size=$((32 * 1024 * 1024))
plain_lvm_size=$((luks_size_bytes - luks_header_size))

esp_image="$work/esp.img"
truncate -s "$esp_size_bytes" "$esp_image"
mkfs.vfat -F 32 -n ESP "$esp_image"
for directory in EFI EFI/systemd EFI/BOOT EFI/Linux loader; do
  mmd -i "$esp_image" "::$directory"
done
mcopy -i "$esp_image" "$systemd_boot" ::EFI/systemd/systemd-bootx64.efi
mcopy -i "$esp_image" "$systemd_boot" ::EFI/BOOT/BOOTX64.EFI
uki_name="ghaf-$version-${root_hash:0:16}.efi"
mcopy -i "$esp_image" "$uki" "::EFI/Linux/$uki_name"
printf 'timeout %s\ndefault %s\neditor no\n' \
  "$boot_timeout" "${uki_name%.efi}" >"$work/loader.conf"
mcopy -i "$esp_image" "$work/loader.conf" ::loader/loader.conf

luks_image="$work/luks.img"
truncate -s "$plain_lvm_size" "$luks_image"
initialize_lvm --image "$luks_image"

# Keep compatibility with Ghaf's existing first-boot enrollment: it unlocks
# this bootstrap slot with an empty passphrase, enrolls TPM2/FIDO2 and recovery
# credentials, then removes the bootstrap slot last.
: >"$work/bootstrap.key"
ghaf-wrap-luks-image \
  --image "$luks_image" \
  --uuid 3E7F3D25-695A-429D-8D34-2D0A18979D7D \
  --key-file "$work/bootstrap.key" \
  --header-size-mib 32
[[ $(stat -c%s "$luks_image") -eq $luks_size_bytes ]] || {
  echo "LUKS image size does not match GPT partition size" >&2
  exit 1
}

dd if="$esp_image" of="$raw" bs=4M seek="$((esp_first * 512))" \
  oflag=seek_bytes conv=notrunc,sparse status=none
dd if="$luks_image" of="$raw" bs=4M seek="$((luks_first * 512))" \
  oflag=seek_bytes conv=notrunc,sparse status=none

bmaptool create "$raw" -o "$output/ghaf-image.bmap"
cores=${NIX_BUILD_CORES:-1}
[[ $cores =~ ^[1-9][0-9]*$ ]] || cores=1
if ((cores > 8)); then cores=8; fi
zstd -T"$cores" --compress "$raw" -o "$output/ghaf-image.raw.zst" --rm
install -m 0644 "$trust_inventory" "$output/public-trust.json"

complete=true
echo "Unsigned x86 image written to $output"
