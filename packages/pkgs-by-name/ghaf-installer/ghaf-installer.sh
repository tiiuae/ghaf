#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Make sure $IMG_PATH env is set
if [ -z "$IMG_PATH" ]; then
  echo "IMG_PATH is not set!"
  exit
fi

usage() {
  echo " "
  echo "Usage: $(basename "$0") [-w] [-e]"
  echo "  -w  Wipe only"
  echo "  -e  Install with disk encryption"
  exit 1
}

WIPE_ONLY=false
ENCRYPTED_INSTALL=false

while getopts "we" opt; do
  case $opt in
  w)
    WIPE_ONLY=true
    ;;
  e)
    ENCRYPTED_INSTALL=true
    ;;
  ?)
    usage
    ;;
  esac
done

# Fails when TERM=`dumb`.
clear || true

cat <<"EOF"
  ,----..     ,---,
 /   /   \  ,--.' |                 .--.,
|   :     : |  |  :               ,--.'  \
.   |  ;. / :  :  :               |  | /\/
.   ; /--`  :  |  |,--.  ,--.--.  :  : :
;   | ;  __ |  :  '   | /       \ :  | |-,
|   : |.' .'|  |   /' :.--.  .-. ||  : :/|
.   | '_.' :'  :  | | | \__\/: . .|  |  .'
'   ; : \  ||  |  ' | : ," .--.; |'  : '
'   | '/  .'|  :  :_:,'/  /  ,.  ||  | |
|   :    /  |  | ,'   ;  :   .'   \  : \
 \   \ .'   `--''     |  ,     .-./  |,'
  `---`                `--`---'   `--'
EOF

echo "Welcome to Ghaf installer!"

echo "To install image or wipe installed image choose path to the device."

hwinfo --disk --short

while true; do
  read -r -p "Device name [e.g. /dev/nvme0n1]: " DEVICE_NAME

  # Input validation: ensure device name starts with /dev/ and contains no path traversal
  if [[ ! $DEVICE_NAME =~ ^/dev/[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid device name format. Device must be in /dev/ and contain only alphanumeric characters, dots, underscores, and dashes."
    continue
  fi

  # Additional security check: ensure the device exists as a block device
  if [ ! -b "$DEVICE_NAME" ]; then
    echo "Device is not a valid block device!"
    continue
  fi

  # Safely get basename to prevent directory traversal
  device_basename=$(basename "$DEVICE_NAME")
  if [ ! -d "/sys/block/$device_basename" ]; then
    echo "Device not found in sysfs!"
    continue
  fi

  # Check if removable
  if [ "$(cat "/sys/block/$device_basename/removable")" != "0" ]; then
    read -r -p "Device provided is removable, do you want to continue? [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY])
      break
      ;;
    *)
      continue
      ;;
    esac
  fi

  break
done

echo "Installing/Deleting Ghaf on $DEVICE_NAME"
read -r -p 'Do you want to continue? [y/N] ' response

case "$response" in
[yY][eE][sS] | [yY]) ;;
*)
  echo "Exiting..."
  exit
  ;;
esac

echo "Wiping device..."

# Deactivate any active LVM volume groups on the device
echo "Deactivating LVM volumes on $DEVICE_NAME..."
for vg in $(pvs --noheadings -o vg_name "$DEVICE_NAME"* 2>/dev/null | sort -u); do
  vgchange -an "$vg" 2>/dev/null || true
done

# Remove LVM physical volumes
echo "Removing LVM signatures..."
pvremove -ff -y "$DEVICE_NAME" "$DEVICE_NAME"* 2>/dev/null || true

# Wipe filesystem and partition signatures
echo "Wiping filesystem signatures..."
wipefs -af "$DEVICE_NAME" 2>/dev/null || true

# Wipe any possible ZFS leftovers from previous installations
# Set sector size to 512 bytes
SECTOR=512
# 10 MiB in 512-byte sectors
MIB_TO_SECTORS=20480
# Disk size in 512-byte sectors
SECTORS=$(blockdev --getsz "$DEVICE_NAME")
# Wipe first 10MiB of disk
dd if=/dev/zero of="$DEVICE_NAME" bs="$SECTOR" count="$MIB_TO_SECTORS" conv=fsync status=none
# Wipe last 10MiB of disk
dd if=/dev/zero of="$DEVICE_NAME" bs="$SECTOR" count="$MIB_TO_SECTORS" seek="$((SECTORS - MIB_TO_SECTORS))" conv=fsync status=none

# Force kernel to re-read partition table
partprobe "$DEVICE_NAME" 2>/dev/null || true

echo "Wipe done."

if [ "$WIPE_ONLY" = true ]; then
  echo "Wipe only option selected. Exiting..."
  echo "Please remove the installation media and reboot"
  exit
fi

echo "Installing..."
shopt -s nullglob
raw_file=("$IMG_PATH"/*.raw.zst)

zstdcat "${raw_file[0]}" | dd of="$DEVICE_NAME" bs=32M status=progress

if [ "$ENCRYPTED_INSTALL" = true ]; then
  echo "Setting up deferred encryption..."

  # Give udev time to process new partitions
  udevadm settle
  sleep 2

  ESP_DEVICE=""
  for i in {1..5}; do
    echo "Attempt $i: Listing partitions for ${DEVICE_NAME}..."

    # Find ESP partition by its partition label (case-insensitive)
    ESP_DEVICE="$(lsblk -pn -o PATH,PARTLABEL "${DEVICE_NAME}" | awk 'tolower($2) ~ /esp/ { print $1; exit }')"

    if [ -n "$ESP_DEVICE" ]; then
      echo "Found ESP partition: $ESP_DEVICE"
      break
    fi

    echo "Waiting for partitions to appear..."
    partprobe "${DEVICE_NAME}"
    sleep 2
  done

  if [ -z "$ESP_DEVICE" ]; then
    echo "Error: Could not find ESP partition by label to create installer marker."
    exit 1
  fi

  mkdir -p /mnt/esp
  mount "$ESP_DEVICE" /mnt/esp || {
    echo "Failed to mount ESP partition"
    exit 1
  }
  touch /mnt/esp/.ghaf-installer-encrypt
  umount /mnt/esp
  echo "Deferred encryption setup complete."
fi

echo "Installation done. Please remove the installation media and reboot"
