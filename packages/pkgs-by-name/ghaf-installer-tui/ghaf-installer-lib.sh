# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-installer-lib.sh — non-TUI installer logic
# Sourced by ghaf-installer-tui.sh. Expects show_error to be defined by the caller.

# =============================================================================
# CORE UTILITIES
# =============================================================================

# shellcheck shell=bash

debug() {
  if [[ -n ${INVOCATION_ID:-} ]]; then
    echo "$*" | systemd-cat -p debug
  fi
}

# =============================================================================
# DEVICE HELPERS
# =============================================================================

# Return the parent disk device backing IMG_PATH (the installer medium).
# Used to exclude the boot drive from the target device list.
# shellcheck disable=SC2329
boot_device() {
  local source parent
  source=$(findmnt -n -o SOURCE --target "${IMG_PATH:-/}" 2>/dev/null) || return 0
  parent=$(lsblk -no pkname "$source" 2>/dev/null | head -1)
  if [[ -n $parent ]]; then
    echo "/dev/$parent"
  else
    echo "$source"
  fi
}

# shellcheck disable=SC2329
list_block_devices() {
  local exclude
  exclude=$(boot_device)
  lsblk -d -n -o PATH,SIZE,TYPE,MODEL | awk -v exclude="$exclude" '$3 == "disk" && $1 != exclude { model=""; for (i=4;i<=NF;i++) model=model (i==4?"":OFS) $i; printf "%-14s %-8s %s\n", $1, $2, model }'
}

# shellcheck disable=SC2329
validate_device() {
  local dev="$1"

  if [[ ! $dev =~ ^/dev/[a-zA-Z0-9._-]+$ ]]; then
    show_error "Invalid device name format."
    return 1
  fi

  if [[ ! -b $dev ]]; then
    show_error "Not a valid block device: $dev"
    return 1
  fi

  local dev_basename
  dev_basename=$(basename "$dev")
  if [[ ! -d /sys/block/$dev_basename ]]; then
    show_error "Device not found in sysfs: $dev"
    return 1
  fi

  return 0
}

# shellcheck disable=SC2329
is_removable() {
  local dev_basename
  dev_basename=$(basename "$1")
  [[ "$(cat "/sys/block/$dev_basename/removable" 2>/dev/null)" != "0" ]]
}

# =============================================================================
# INSTALLATION OPERATIONS
# =============================================================================

# Wipe all signatures, LVM metadata, and first/last 10 MiB of device
# shellcheck disable=SC2329
do_wipe() {
  local dev="$1"
  debug "Wiping device: $dev"

  # Deactivate any active LVM volume groups on the device
  for vg in $(pvs --noheadings -o vg_name "$dev"* 2>/dev/null | sort -u); do
    run_spin -q "Deactivating volume group $vg..." vgchange -an "$vg"
  done

  run_spin -q "Removing LVM metadata from $dev..." pvremove -ff -y "$dev" "$dev"* 2>/dev/null
  run_spin -q "Wiping signatures on $dev..." wipefs -af "$dev"

  local sector=512
  local mib_sectors=20480
  local total_sectors
  total_sectors=$(blockdev --getsz "$dev")

  run_spin "Zeroing $dev..." dd if=/dev/zero of="$dev" bs="$sector" count="$mib_sectors" conv=fsync status=none
  run_spin "Zeroing end of $dev..." dd if=/dev/zero of="$dev" bs="$sector" count="$mib_sectors" \
    seek="$((total_sectors - mib_sectors))" conv=fsync status=none

  run_spin -q "Re-reading partition table on $dev..." partprobe "$dev"
  debug "Wipe complete: $dev"
}

# Find the ESP partition on a device by PARTLABEL, retrying up to 5 times
# shellcheck disable=SC2329
find_esp_device() {
  local dev="$1"
  local esp_device=""

  for i in {1..5}; do
    debug "Attempt $i: looking for ESP on $dev"
    esp_device="$(lsblk -pn -o PATH,PARTLABEL "$dev" | awk 'tolower($2) ~ /esp/ { print $1; exit }')"
    if [[ -n $esp_device && -b $esp_device ]]; then
      debug "Found ESP: $esp_device"
      printf '%s\n' "$esp_device"
      return 0
    fi
    run_spin -q "Re-reading partition table..." partprobe "$dev"
    run_spin -q "Waiting for partitions to settle..." sleep 2
  done

  return 1
}

# Decompress and write the raw image to the target device.
# Uses bmaptool for a sparse-aware copy when a .bmap file is available,
# piping directly from zstdcat so no temp storage is needed.
# Falls back to a streaming dd write if bmaptool is unavailable or fails.
# shellcheck disable=SC2329
do_install_image() {
  local dev="$1"

  shopt -s nullglob
  local -a raw_files=("$IMG_PATH"/*.raw.zst)
  shopt -u nullglob

  if [[ ${#raw_files[@]} -eq 0 ]]; then
    show_error "No .raw.zst image found in $IMG_PATH"
    return 1
  fi

  local raw_file="${raw_files[0]}"
  local bmap_file="${raw_file%.raw.zst}.bmap"

  local IMGSIZE
  if [[ -s $bmap_file ]]; then
    IMGSIZE="$(grep -oP '<ImageSize>\s*\K\d+' "$bmap_file")"
  else
    show_info "Estimating image size..." ""
    IMGSIZE="$(zstd -l "$raw_file" -v 2>/dev/null | awk '/Decompressed Size:/ {print $5}' | tr -d '()')"
  fi

  local -a PV_CMD
  PV_CMD=(pv --format '%{sgr:white,bold}Writing Ghaf image to disk - %r %40p %e%{sgr:reset}' -N "$raw_file")
  [[ -n $IMGSIZE ]] && PV_CMD+=(-s "$IMGSIZE")

  if command -v bmaptool >/dev/null 2>&1 && [[ -s $bmap_file ]]; then
    debug "Using bmaptool with block map: $bmap_file"
    if zstdcat -T0 "$raw_file" | "${PV_CMD[@]}" | bmaptool copy --bmap "$bmap_file" - "$dev" >/dev/null 2>&1; then
      return 0
    fi
    debug "bmaptool failed, falling back to streaming write"
    show_warning "Fast installation unavailable. Continuing with standard installation."
  fi

  debug "Writing image: $raw_file -> $dev"
  zstdcat -T0 "$raw_file" | "${PV_CMD[@]}" | dd of="$dev" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
}

# Place a deferred encryption marker on the ESP partition
# shellcheck disable=SC2329
do_setup_encryption() {
  local dev="$1"

  run_spin "Settling block devices..." udevadm settle
  run_spin "Waiting for partitions..." sleep 2

  local esp_dev
  esp_dev=$(find_esp_device "$dev") || {
    show_error "Could not find ESP partition for encryption marker."
    return 1
  }

  mkdir -p /mnt/esp
  mount -t vfat "$esp_dev" /mnt/esp || {
    show_error "Failed to mount ESP partition: $esp_dev"
    return 1
  }

  touch /mnt/esp/.ghaf-installer-encrypt
  umount /mnt/esp
  debug "Deferred encryption marker placed on ESP."
}

# Returns 0 if the firmware is in Secure Boot Setup Mode, 1 otherwise.
# Requires efivarfs to be mounted and efitools available.
# shellcheck disable=SC2329
system_in_setup_mode() {
  if ! mountpoint -q /sys/firmware/efi/efivars; then
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars
  fi

  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    debug "EFI variables not available. Ensure the installer booted in UEFI mode."
    return 1
  fi

  local setup_mode_file
  setup_mode_file="$(find /sys/firmware/efi/efivars -maxdepth 1 -name 'SetupMode-*' -print -quit 2>/dev/null)"
  if [[ -n $setup_mode_file ]]; then
    local setup_mode
    setup_mode="$(od -An -t u1 -j 4 -N 1 "$setup_mode_file" 2>/dev/null | tr -d '[:space:]')"
    [[ $setup_mode == "1" ]]
  else
    local pk_output
    pk_output="$(efi-readvar -v PK 2>&1 || true)"
    # No PK entries means Setup Mode
    [[ -z $pk_output ]] || echo "$pk_output" | grep -qi "has no entries"
  fi
}

# Enroll Secure Boot keys from /etc/ghaf/secureboot/keys
# shellcheck disable=SC2329
do_enroll_secureboot() {
  local keys_dir="/etc/ghaf/secureboot/keys"
  local pk_auth="$keys_dir/PK.auth"
  local kek_auth="$keys_dir/KEK.auth"
  local db_auth="$keys_dir/db.auth"

  # Verify the firmware is in Setup Mode before enrolling
  system_in_setup_mode || return 1

  for key_file in "$pk_auth" "$kek_auth" "$db_auth"; do
    if [[ ! -f $key_file ]]; then
      show_error "Missing key file: $key_file"
      return 1
    fi
  done

  # Remove immutable flags before writing EFI variables
  shopt -s nullglob
  local -a efi_vars
  for pattern in db KEK PK; do
    # shellcheck disable=SC2206
    efi_vars=(/sys/firmware/efi/efivars/${pattern}-*)
    [[ ${#efi_vars[@]} -gt 0 ]] && chattr -i "${efi_vars[@]}" || true
  done
  shopt -u nullglob

  local -a key_vars=(db KEK PK)
  local -A key_files=([db]="$db_auth" [KEK]="$kek_auth" [PK]="$pk_auth")

  for var in "${key_vars[@]}"; do
    run_spin -q "Enrolling $var key..." efi-updatevar -f "${key_files[$var]}" "$var" || {
      show_error "Failed to enroll $var"
      return 1
    }
  done

  for var in "${key_vars[@]}"; do
    run_spin -q "Verifying $var..." efi-readvar -v "$var" >/dev/null 2>&1 || {
      show_error "$var verification failed"
      return 1
    }
  done

  debug "Secure Boot keys enrolled."
}
