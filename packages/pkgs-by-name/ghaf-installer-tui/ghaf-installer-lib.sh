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
  # Netboot: the image arrives over the network, so there is no installer medium
  # to exclude and every disk is a legitimate target. Returning empty is the
  # correct answer here, not a failure -- findmnt on a URL would fall through to
  # the `|| return 0` below anyway, but only by accident.
  [[ ${IMG_PATH:-} =~ ^https?:// ]] && return 0
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

# Work out where the image is coming from, and make sure the block map is a
# local seekable file either way. Sets GHAF_REMOTE / GHAF_RAW_SRC / GHAF_BMAP.
#
# IMG_PATH is either a directory (booted from the ISO, which carries the image)
# or an http(s) base URL (netboot, where the image is fetched at install time
# and never embedded -- that is the whole point of netboot: the boot artefacts
# stay ~1.5 GB instead of ~7 GB).
# shellcheck disable=SC2329
resolve_image_source() {
  local cmdline_url bmap_url

  # A ghaf.image_url= kernel parameter beats the built-in default, so a single
  # netboot artefact can serve every target and the server picks. Parsed here
  # rather than injected via the unit's Environment= so that the TUI and the
  # scripted installer share exactly one code path.
  cmdline_url=$(sed -n 's/.*[[:space:]]ghaf\.image_url=\([^[:space:]]*\).*/\1/p' /proc/cmdline 2>/dev/null)
  [[ -n $cmdline_url ]] && IMG_PATH="$cmdline_url"

  if [[ ${IMG_PATH:-} =~ ^https?:// ]]; then
    GHAF_REMOTE=true
    if [[ $IMG_PATH == *.raw.zst ]]; then
      GHAF_RAW_SRC="$IMG_PATH"
    else
      GHAF_RAW_SRC="${IMG_PATH%/}/ghaf-image.raw.zst"
    fi
    bmap_url="${GHAF_RAW_SRC%.raw.zst}.bmap"

    # bmaptool needs the map as a seekable local file; it is only ~50 KB, so
    # /run (RAM-backed) is the right home and nothing touches the target disk.
    # Overridable so this path can be exercised without root in tests.
    local rundir="${GHAF_INSTALLER_RUNDIR:-/run/ghaf-installer}"
    GHAF_BMAP="$rundir/ghaf-image.bmap"
    if ! mkdir -p "$rundir"; then
      show_error "Could not create $rundir for the block map"
      return 1
    fi
    if ! curl -fsSL --connect-timeout 10 --retry 5 --retry-delay 2 --retry-all-errors -o "$GHAF_BMAP" "$bmap_url"; then
      # Deliberately fatal rather than falling back to an unverified dd. The
      # bmap carries per-range sha256 checksums that bmaptool verifies while
      # copying, and over plain HTTP that is the only integrity check there is.
      show_error "Could not fetch block map $bmap_url"
      return 1
    fi
  else
    GHAF_REMOTE=false
    shopt -s nullglob
    local -a raw_files=("$IMG_PATH"/*.raw.zst)
    shopt -u nullglob

    if [[ ${#raw_files[@]} -eq 0 ]]; then
      show_error "No .raw.zst image found in $IMG_PATH"
      return 1
    fi

    GHAF_RAW_SRC="${raw_files[0]}"
    GHAF_BMAP="${GHAF_RAW_SRC%.raw.zst}.bmap"
  fi
}

# Produce the decompressed image on stdout, from disk or from the network.
# shellcheck disable=SC2329
feed_image() {
  if [[ ${GHAF_REMOTE:-false} == true ]]; then
    # --no-progress-meter: pv already draws the progress bar the TUI shows, and
    # curl's own meter would scribble over it on the same tty.
    #
    # No --retry: this feeds `pv | bmaptool copy - <dev>`, and a retry after the
    # first bytes restarts the response into the same pipe. Wait before the
    # transfer instead -- do_install_image calls wait_for_image_slot.
    curl -fL --no-progress-meter --connect-timeout 10 "$GHAF_RAW_SRC"
  else
    cat "$GHAF_RAW_SRC"
  fi | zstdcat -T0
}

# Decompressed size of the image about to be written, or empty. Used both to
# refuse an oversized image and to give pv a total.
# shellcheck disable=SC2329
image_size_bytes() {
  if [[ -s ${GHAF_BMAP:-} ]]; then
    # || true: no match exits 1, which under `set -euo pipefail` would abort the
    # install over a size estimate.
    grep -oP '<ImageSize>\s*\K\d+' "$GHAF_BMAP" 2>/dev/null | head -1 || true
  elif [[ ${GHAF_REMOTE:-false} == false ]]; then
    # `zstd -l` needs a seekable file, so this is local-only. The remote path
    # always has a bmap by now, or resolve_image_source bailed.
    zstd -l "$GHAF_RAW_SRC" -v 2>/dev/null | awk '/Decompressed Size:/ {print $5}' | tr -d '()' || true
  fi
}

# Refuse an image too big for the target before the wipe destroys anything.
# shellcheck disable=SC2329
do_check_capacity() {
  local dev="$1" reason

  resolve_image_source || return 1

  show_info "Checking the image fits..." ""
  GHAF_IMGSIZE="$(image_size_bytes)"

  if ! reason="$(image_fits_device "$GHAF_IMGSIZE" "$dev" 2>&1)"; then
    show_error "The image does not fit $dev: $reason"
    return 1
  fi
  [[ -z $reason ]] || debug "capacity: $reason"
}

# Decompress and write the raw image to the target device.
# Uses bmaptool for a sparse-aware copy when a .bmap file is available,
# piping directly from the producer so no temp storage is needed.
# Falls back to a streaming dd write if bmaptool is unavailable or fails.
# shellcheck disable=SC2329
do_install_image() {
  local dev="$1"

  resolve_image_source || return 1

  # A fleet server answers 503 until this machine's turn. Inside the function,
  # not hoisted: the bmaptool->dd fallback re-fetches and needs its own slot.
  if [[ ${GHAF_REMOTE:-false} == true ]]; then
    wait_for_image_slot "$GHAF_RAW_SRC" || {
      show_error "Could not get an image download slot from the install server."
      return 1
    }
  fi

  local IMGSIZE
  IMGSIZE="${GHAF_IMGSIZE:-$(image_size_bytes)}"

  local -a PV_CMD
  PV_CMD=(pv --format '%{sgr:white,bold}Writing Ghaf image to disk - %r %40p %e%{sgr:reset}' -N "$GHAF_RAW_SRC")
  [[ -n $IMGSIZE ]] && PV_CMD+=(-s "$IMGSIZE")

  if command -v bmaptool >/dev/null 2>&1 && [[ -s $GHAF_BMAP ]]; then
    debug "Using bmaptool with block map: $GHAF_BMAP"
    local bmap_err reason
    bmap_err="$(mktemp)"
    # stderr to a file, not /dev/null: it cannot go to the screen without
    # corrupting the TUI, and discarded it leaves "falling back" as the only
    # symptom -- which cannot tell a missing tool from a checksum mismatch.
    if feed_image | "${PV_CMD[@]}" | bmaptool copy --bmap "$GHAF_BMAP" - "$dev" >/dev/null 2>"$bmap_err"; then
      rm -f "$bmap_err"
      return 0
    fi
    debug "bmaptool failed: $(tr '\n' ' ' <"$bmap_err")"
    reason="$(grep -v '^[[:space:]]*$' "$bmap_err" | tail -1 | cut -c1-120 || true)"
    rm -f "$bmap_err"
    # No dd fallback here. bmaptool ran and the image did not verify, and its
    # per-range sha256 is the only integrity check an image fetched over plain
    # HTTP gets -- which is why resolve_image_source already treats a MISSING
    # bmap as fatal. Rewriting the same bytes unverified defeats both.
    show_error "Image verification failed${reason:+: $reason}"
    return 1
  fi

  # Reached only with no bmaptool or no bmap, i.e. verification was never
  # available. Not the netboot path, where resolve_image_source requires one.
  debug "Writing image: $GHAF_RAW_SRC -> $dev"
  feed_image | "${PV_CMD[@]}" | dd of="$dev" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
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

# Verify the written image, then enroll its matching Secure Boot keys.
# shellcheck disable=SC2329
do_enroll_secureboot() {
  local dev="$1"
  local keys_dir="${GHAF_SECUREBOOT_KEY_DIR:-/etc/ghaf/secureboot/keys}"
  local pk_auth="$keys_dir/PK.auth"
  local kek_auth="$keys_dir/KEK.auth"
  local db_auth="$keys_dir/db.auth"
  local esp_dev

  run_spin -q "Settling block devices..." udevadm settle
  esp_dev="$(find_esp_device "$dev")" || {
    show_error "Could not find ESP partition for Secure Boot verification."
    return 1
  }
  verify_secureboot_esp "$esp_dev" "$keys_dir" || return 1

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

# Create or reuse the EFI entry for the ESP just written, first in BootOrder.
# Without it the machine boots the installer media it is still sitting in.
# shellcheck disable=SC2329
do_set_boot_entry() {
  local dev="$1" esp
  udevadm settle
  if ! esp="$(find_esp_device "$dev")"; then
    show_warning "Could not find the ESP; leaving the boot order untouched."
    return 0
  fi
  set_boot_to_disk "$dev" "$esp" || true
}
