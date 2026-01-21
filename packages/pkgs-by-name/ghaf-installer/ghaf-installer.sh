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
  echo "Usage: $(basename "$0") [-w] [-e] [-s]"
  echo "  -w  Wipe only"
  echo "  -e  Install with disk encryption"
  echo "  -s  Install with Secure Boot enrollment"
  exit 1
}

WIPE_ONLY=false
ENCRYPTED_INSTALL=false
SECUREBOOT_INSTALL=false

while getopts "wes" opt; do
  case $opt in
  w)
    WIPE_ONLY=true
    ;;
  e)
    ENCRYPTED_INSTALL=true
    ;;
  s)
    SECUREBOOT_INSTALL=true
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
shopt -u nullglob

if [ ${#raw_file[@]} -eq 0 ]; then
  echo "No .raw.zst image found in $IMG_PATH"
  exit 1
fi

zstdcat "${raw_file[0]}" | dd of="$DEVICE_NAME" bs=32M status=progress

find_esp_device() {
  local esp_device=""

  for i in {1..5}; do
    echo "Attempt $i: Listing partitions for ${DEVICE_NAME}..." >&2

    # Find ESP partition by its partition label (case-insensitive)
    esp_device="$(lsblk -pn -o PATH,PARTLABEL "${DEVICE_NAME}" | awk 'tolower($2) ~ /esp/ { print $1; exit }')"

    if [ -n "$esp_device" ] && [ -b "$esp_device" ]; then
      echo "Found ESP partition: $esp_device" >&2
      printf '%s\n' "$esp_device"
      return 0
    fi

    echo "Waiting for partitions to appear..." >&2
    partprobe "${DEVICE_NAME}"
    sleep 2
  done

  return 1
}

if [ "$ENCRYPTED_INSTALL" = true ]; then
  echo "Setting up deferred encryption..."

  # Give udev time to process new partitions
  udevadm settle
  sleep 2

  ESP_DEVICE="$(find_esp_device)" || {
    echo "Error: Could not find ESP partition by label to create installer marker."
    exit 1
  }

  mkdir -p /mnt/esp
  mount -t vfat "$ESP_DEVICE" /mnt/esp || {
    echo "Failed to mount ESP partition"
    exit 1
  }
  touch /mnt/esp/.ghaf-installer-encrypt
  umount /mnt/esp
  echo "Deferred encryption setup complete."
fi

if [ "$SECUREBOOT_INSTALL" = true ]; then
  echo "Setting up Secure Boot enrollment..."

  KEYS_DIR="/etc/ghaf/secureboot/keys"
  PK_AUTH="$KEYS_DIR/PK.auth"
  KEK_AUTH="$KEYS_DIR/KEK.auth"
  DB_AUTH="$KEYS_DIR/db.auth"

  if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "EFI variables not available. Ensure the installer booted in UEFI mode."
    exit 1
  fi

  if ! mountpoint -q /sys/firmware/efi/efivars; then
    echo "Mounting efivarfs..."
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars
  fi

  if ! command -v efi-updatevar >/dev/null 2>&1 || ! command -v efi-readvar >/dev/null 2>&1; then
    echo "efitools is not available in the installer environment."
    exit 1
  fi

  setup_mode_file="$(find /sys/firmware/efi/efivars -maxdepth 1 -name 'SetupMode-*' -print -quit 2>/dev/null)"
  if [ -n "$setup_mode_file" ]; then
    setup_mode="$(od -An -t u1 -j 4 -N 1 "$setup_mode_file" 2>/dev/null | tr -d '[:space:]')"
    if [ "$setup_mode" != "1" ]; then
      echo "System is not in Setup Mode. Enable Setup Mode in BIOS first."
      exit 1
    fi
  else
    pk_output="$(efi-readvar -v PK 2>&1 || true)"
    if echo "$pk_output" | grep -qi "has no entries"; then
      echo "Platform key (PK) is empty (Setup Mode)."
    elif [ -n "$pk_output" ]; then
      echo "Platform key (PK) present. System is not in Setup Mode."
      echo "Clear PK in firmware setup to enroll new keys."
      exit 1
    fi
  fi

  for key_file in "$PK_AUTH" "$KEK_AUTH" "$DB_AUTH"; do
    if [ ! -f "$key_file" ]; then
      echo "Missing key file: $key_file"
      exit 1
    fi
  done

  echo "Enrolling Secure Boot keys from $KEYS_DIR..."
  shopt -s nullglob
  db_vars=(/sys/firmware/efi/efivars/db-*)
  kek_vars=(/sys/firmware/efi/efivars/KEK-*)
  pk_vars=(/sys/firmware/efi/efivars/PK-*)
  if [ ${#db_vars[@]} -gt 0 ]; then
    chattr -i "${db_vars[@]}" || true
  fi
  if [ ${#kek_vars[@]} -gt 0 ]; then
    chattr -i "${kek_vars[@]}" || true
  fi
  if [ ${#pk_vars[@]} -gt 0 ]; then
    chattr -i "${pk_vars[@]}" || true
  fi
  shopt -u nullglob
  efi-updatevar -f "$DB_AUTH" db || {
    echo "Failed to enroll db"
    exit 1
  }
  efi-updatevar -f "$KEK_AUTH" KEK || {
    echo "Failed to enroll KEK"
    exit 1
  }
  efi-updatevar -f "$PK_AUTH" PK || {
    echo "Failed to enroll PK"
    exit 1
  }

  echo "Verifying Secure Boot key enrollment..."
  efi-readvar -v db >/dev/null 2>&1 || {
    echo "db verification failed"
    exit 1
  }
  efi-readvar -v KEK >/dev/null 2>&1 || {
    echo "KEK verification failed"
    exit 1
  }
  efi-readvar -v PK >/dev/null 2>&1 || {
    echo "PK verification failed"
    exit 1
  }
  echo "Secure Boot keys enrolled."
fi

echo "Installation done. Please remove the installation media and reboot"
