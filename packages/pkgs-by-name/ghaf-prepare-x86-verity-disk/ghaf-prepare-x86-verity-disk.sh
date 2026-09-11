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
  [--disk BLOCK_DEVICE --output DIR] [--print-plan]

Populates a disposable build-VM disk with unsigned x86 GPT/FAT/LUKS/LVM.
--print-plan validates inputs without a VM. The Nix builder starts the VM
and compresses the completed disk after it exits successfully.
EOF
  exit 2
}

disk="" update_dir="" systemd_boot="" trust_inventory="" output="" boot_timeout=""
image_size_mib="" root_size_mib="" verity_size_mib="" swap_size_mib="" persist_size_mib=""
print_plan=false
while (($#)); do
  case "$1" in
  --print-plan)
    print_plan=true
    shift
    ;;
  --disk | --update-dir | --systemd-boot | --trust-inventory | --output | --boot-timeout | \
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
  ghaf-initialize-verity-lvm --manifest "$manifest" \
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
[[ -b $disk && $EUID -eq 0 ]] || usage
[[ $(blockdev --getsize64 "$disk") -eq $((image_size_mib * 1048576)) ]] || usage
[[ -z $(wipefs --noheadings --output TYPE "$disk") ]] || {
  echo "Refusing nonempty disk" >&2
  exit 1
}
raw=$disk
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

blockdev --rereadpt "$disk"
esp_image="${disk}1"
luks_image="${disk}2"
[[ -b $esp_image && -b $luks_image ]] || {
  echo "Partition devices missing" >&2
  exit 1
}
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

# The empty bootstrap passphrase is replaced by first-boot enrollment.
: >"$work/bootstrap.key"
initialize_lvm --image "$luks_image" \
  --luks-uuid 3E7F3D25-695A-429D-8D34-2D0A18979D7D --key-file "$work/bootstrap.key"

install -m 0644 "$trust_inventory" "$output/public-trust.json"

complete=true
echo "Unsigned x86 disk populated on $disk"
