#!/usr/bin/env bash
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  echo "Usage: $(basename "$0") [-w]"
  echo "  -w  Wipe only"
  exit 1
}

WIPE_ONLY=false

while getopts "w" opt; do
  case $opt in
  w)
    WIPE_ONLY=true
    ;;
  ?)
    usage
    ;;
  esac
done

clear

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

  if [ ! -d "/sys/block/$(basename "$DEVICE_NAME")" ]; then
    echo "Device not found!"
    continue
  fi

  # Check if removable
  if [ "$(cat "/sys/block/$(basename "$DEVICE_NAME")/removable")" != "0" ]; then
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
echo "Wipe done."

if [ "$WIPE_ONLY" = true ]; then
  echo "Wipe only option selected. Exiting..."
  echo "Please remove the installation media and reboot"
  exit
fi

echo "Installing..."
zstdcat "$IMG_PATH" | dd of="$DEVICE_NAME" bs=32M status=progress

echo "Installation done. Please remove the installation media and reboot"
