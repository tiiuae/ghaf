#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
ENDCOLOR='\e[0m'
FORCE=false
IMGSIZE=""

error() { echo -e "${RED}$*${ENDCOLOR}"; }
success() { echo -e "${GREEN}$*${ENDCOLOR}"; }
warn() { echo -e "${YELLOW}$*${ENDCOLOR}"; }
clear_lines() {
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

  Example:
    $(basename "$0") -d /dev/sda -i <IMAGE_FILE>.zst

EOF
  exit 1
}

deps=(zstd awk tr dd blkdiscard lsblk numfmt stat blockdev sync umount)
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
while getopts "d:i:f" opt; do
  case $opt in
  d) DEVICE="$OPTARG" ;;
  i) FILENAME="$OPTARG" ;;
  f) FORCE=true ;;
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
  Image :  $FILENAME
    Size:  $img_size
  Target:  $DEVICE
    Size:  $dev_size
===============================================

"
}

ask_confirmation() {
  warn "WARNING: This will erase ALL DATA on $DEVICE"
  read -p "Proceed? (Y): " -n 1 -r
  clear_lines 9
  if [[ $REPLY != "Y" ]]; then
    echo "Flashing aborted."
    exit 0
  fi
}

# Function to wipe any ZFS leftovers existing on the disk
wipe_filesystem() {
  show_summary
  $FORCE || ask_confirmation
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
  umount -q "$DEVICE"* || true
  # Wipe first 10MiB of disk
  dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" conv=fsync status=none
  # Wipe last 10MiB of disk
  dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" seek="$((SECTORS - MIB_TO_SECTORS))" conv=fsync status=none
  clear_lines 1
  echo "Flashing..."
}

USE_PV=false
command -v pv >/dev/null 2>&1 && USE_PV=true

case "$FILENAME" in
*.zst)
  echo "Estimating uncompressed size..."
  IMGSIZE="$(zstd -l "$FILENAME" -v 2>/dev/null | awk '/Decompressed Size:/ {print $5}' | tr -d '()')"
  clear_lines 1
  wipe_filesystem

  if $USE_PV; then
    PV_CMD=(pv -tpreb -N "$FILENAME")
    [[ -n $IMGSIZE ]] && PV_CMD+=(-s "$IMGSIZE")
    zstdcat "$FILENAME" | "${PV_CMD[@]}" | dd of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
  else
    zstdcat "$FILENAME" | dd of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=progress
  fi
  ;;
*.iso | *.img)
  IMGSIZE="$(stat -c%s "$FILENAME")"
  wipe_filesystem

  if $USE_PV; then
    pv -tpreb "$FILENAME" -N "$FILENAME" -s "$IMGSIZE" | dd of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=none
  else
    dd if="$FILENAME" of="$DEVICE" bs=32M conv=fsync oflag=direct iflag=fullblock status=progress
  fi
  ;;
*)
  error "Unsupported file format"
  exit 1
  ;;
esac
sync
$USE_PV && clear_lines 2
success "Flashing complete"
