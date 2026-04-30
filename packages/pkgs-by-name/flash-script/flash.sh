#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Only emit ANSI formatting when stdout is a terminal.
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  ENDCOLOR='\e[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  ENDCOLOR=''
fi
FORCE=false
NON_INTERACTIVE=false
[ ! -t 2 ] && NON_INTERACTIVE=true
PROGRESS_INTERVAL=5
IMGSIZE=""
TEMP_DIR=""
SPARSE_IMAGE=""
SPARSE_BMAP=""
PREBUILT_BMAP=""

error() { echo -e "${RED}$*${ENDCOLOR}"; }
success() { echo -e "${GREEN}$*${ENDCOLOR}"; }
warn() { echo -e "${YELLOW}$*${ENDCOLOR}"; }
clear_lines() {
  [ -t 1 ] && ! $NON_INTERACTIVE || return 0
  for ((i = 0; i < $1; i++)); do printf "\033[2K\033[1A\033[G"; done
  printf "\033[2K\033[G"
}

# Function to print usage and exit
help_msg() {
  cat <<EOF
  Usage: $(basename "$0") -d <DISK> -i <IMAGE>

  Flash the provided Ghaf image to the selected device.

  Options:
    -d      Target device.

    -i      Image file.

    -f      Force operation. Will not prompt the user for confirmation.

    -n      Non-interactive mode. Progress is emitted as plain newline-terminated
            log lines instead of a live terminal display, pv is not used. Use this
            in CI/CD pipelines (e.g. Jenkins) where there is no TTY.

    -p      Progress interval in seconds for non-interactive mode (default: 5).

  Example:
    $(basename "$0") -d /dev/sda -i <IMAGE_FILE>.zst

EOF
  exit 1
}

deps=(zstd awk tr dd blkdiscard lsblk numfmt stat blockdev sync umount grep bmaptool)
# Check dependencies
for cmd in "${deps[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    cat >&2 <<EOF
Error: $cmd not found in PATH.

Please install it with your package manager (e.g., apt, yum, brew).

Alternatively, if using nix, you can run this script inside a temporary nix-shell:
    nix-shell -p $cmd --run "bash $0"
EOF
    exit 1
  fi
done

if [ "$EUID" -ne 0 ]; then
  error "Please run as root"
  exit 1
fi

# Parse the parameters
while getopts "d:i:fnp:" opt; do
  case $opt in
  d) DEVICE="$OPTARG" ;;
  i) FILENAME="$OPTARG" ;;
  f) FORCE=true ;;
  n) NON_INTERACTIVE=true ;;
  p)
    if ! [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
      error "Invalid progress interval: '${OPTARG}' (must be a positive integer)"
      exit 1
    fi
    PROGRESS_INTERVAL="$OPTARG"
    ;;
  *) help_msg ;;
  esac
done

# Input validation for device parameter
if [[ ! $DEVICE =~ ^/dev/(sd[a-z]|nvme[0-9]+n[0-9]+|mmcblk[0-9]+|vd[a-z]|loop[0-9]+)$ ]]; then
  error "Invalid device path format: ${DEVICE}"
  exit 1
fi

# Check if disk exists and is a block device
if [ ! -b "$DEVICE" ]; then
  error "No such block device: ${DEVICE}"
  exit 1
fi

# Input validation for filename parameter
if [[ $FILENAME =~ \.\./ || $FILENAME =~ /\.\. || $FILENAME == ".." ]]; then
  error "Invalid filename contains path traversal: ${FILENAME}"
  exit 1
fi

if [ ! -f "$FILENAME" ]; then
  error "No such file: ${FILENAME}"
  exit 1
fi

show_summary() {
  local img_size="${IMGSIZE:-Unknown}"
  img_size=$(numfmt --to=iec <<<"$img_size" 2>/dev/null || echo "$img_size")
  dev_size="$(lsblk -no SIZE "$DEVICE" | head -n 1)"
  printf "%b" "
================ FLASH SUMMARY ================
   Image:  $FILENAME
    Size:  $img_size
  Target:  $DEVICE
    Size:  $dev_size
===============================================

"
}

cleanup() {
  if [ -n "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

unmount_device_tree() {
  mapfile -t mounted_nodes < <(lsblk -nrpo NAME,MOUNTPOINTS "$DEVICE" | awk 'NF > 1 { print $1 }' | tac)
  for node in "${mounted_nodes[@]}"; do
    umount -q "$node" || true
  done
}

confirm_flash() {
  warn "WARNING: This will erase ALL DATA on $DEVICE"
  read -p "Proceed? (Y): " -n 1 -r
  clear_lines 9
  if [[ $REPLY != "Y" ]]; then
    echo "Flashing aborted."
    exit 0
  fi
}

wipe_device() {
  echo "Wiping filesystem..."

  blkdiscard -f "$DEVICE" &>/dev/null || true

  # Set sector size to 512 bytes
  SECTOR=512
  # 10 MiB in 512-byte sectors
  MIB_TO_SECTORS=20480
  # Disk size in 512-byte sectors
  SECTORS=$(blockdev --getsz "$DEVICE")
  # Unmount possible mounted filesystems
  sync
  unmount_device_tree
  blockdev --flushbufs "$DEVICE" || true
  # Wipe first 10MiB of disk
  dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" conv=fsync status=none
  # Wipe last 10MiB of disk
  dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" seek="$((SECTORS - MIB_TO_SECTORS))" conv=fsync status=none
  clear_lines 1
  echo "Flashing..."
}

USE_PV=false
command -v pv >/dev/null 2>&1 && USE_PV=true

dd_with_progress() {
  dd "$@" 2> >(grep -v records >&2) &
  local dd_pid=$!

  while kill -0 "$dd_pid" 2>/dev/null; do
    sleep "$PROGRESS_INTERVAL"
    # SIGUSR1 causes dd to print its current statistics to stderr as one line
    kill -USR1 "$dd_pid" 2>/dev/null || true
  done

  wait "$dd_pid"
}

flash_zst_with_bmap() {
  wipe_device
  TEMP_DIR="$(mktemp -d -t ghaf-flash.XXXXXX)"
  SPARSE_IMAGE="$(basename "$FILENAME")"
  SPARSE_IMAGE="$TEMP_DIR/${SPARSE_IMAGE%%.*}.raw"

  echo "Preparing sparse image for faster flashing..."
  zstdcat "$FILENAME" | dd_with_progress of="$SPARSE_IMAGE" bs=32M conv=sparse,fsync iflag=fullblock status=none
  PREBUILT_BMAP="${FILENAME%%.*}.bmap"
  if [ -f "$PREBUILT_BMAP" ]; then
    SPARSE_BMAP="$PREBUILT_BMAP"
    echo "Using prebuilt block map: $SPARSE_BMAP"
  else
    SPARSE_BMAP="$SPARSE_IMAGE.bmap"
    echo "Generating block map..."
    bmaptool create -o "$SPARSE_BMAP" "$SPARSE_IMAGE" >/dev/null
  fi
  echo "Flashing with sparse-aware copy..."
  if ! bmaptool copy --bmap "$SPARSE_BMAP" "$SPARSE_IMAGE" "$DEVICE"; then
    warn "Sparse-aware flashing failed, likely because the device is still busy."
    return 1
  fi
}

flash_zst_stream() {
  wipe_device
  if $USE_PV && ! $NON_INTERACTIVE; then
    PV_CMD=(pv -tpreb -N "$FILENAME")
    [[ -n $IMGSIZE ]] && PV_CMD+=(-s "$IMGSIZE")
    zstdcat "$FILENAME" | "${PV_CMD[@]}" | dd of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
  else
    zstdcat "$FILENAME" | dd_with_progress of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock
  fi
}

flash_raw_stream() {
  wipe_device
  if $USE_PV && ! $NON_INTERACTIVE; then
    pv -tpreb "$FILENAME" -N "$FILENAME" -s "$IMGSIZE" | dd of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
  else
    dd_with_progress if="$FILENAME" of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock
  fi
}

case "$FILENAME" in
*.zst)
  echo "Estimating uncompressed size..."
  IMGSIZE="$(zstd -l "$FILENAME" -v 2>/dev/null | awk '/Decompressed Size:/ {print $5}' | tr -d '()')"
  clear_lines 1
  show_summary
  $FORCE || confirm_flash

  if ! flash_zst_with_bmap; then
    warn "Falling back to streaming dd."
    flash_zst_stream
  fi
  ;;
*.iso | *.img)
  IMGSIZE="$(stat -c%s "$FILENAME")"
  show_summary
  $FORCE || confirm_flash
  flash_raw_stream
  ;;
*)
  error "Unsupported file format"
  exit 1
  ;;
esac
sync
$USE_PV && clear_lines 2
success "Flashing complete"
