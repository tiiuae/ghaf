#!/usr/bin/env bash
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Function to print usage and exit
print_usage() {
    echo "Usage: $0 -d <disk> -i <imagefile>"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
  exit
fi

# Check the number of parameters
if [ "$#" -ne 4 ]; then
    print_usage
fi

# Parse the parameters
while getopts "d:i:" opt; do
    case $opt in
        d) DEVICE="$OPTARG" ;;
        i) FILENAME="$OPTARG" ;;
        *) print_usage ;;
    esac
done

# Check if disk and imagefile exist
if [ ! -e "$DEVICE" ]; then
    echo "No such block device: ${DEVICE}"
    exit 1
fi

if [ ! -e "$FILENAME" ]; then
    echo "No such file: ${FILENAME}"
    exit 1
fi

# Function to wipe any ZFS leftovers exising on the disk
wipe_filesystem () {
    echo "Wiping filesystem..."
    # Set sector size to 512 bytes
    SECTOR=512
    # 10 MiB in 512-byte sectors
    MIB_TO_SECTORS=20480
    # Disk size in 512-byte sectors
    SECTORS=$(blockdev --getsz "$DEVICE")
    # Unmount possible mounted filesystems
    sync; umount -q "$DEVICE"* || true;
    # Wipe first 10MiB of disk
    dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" conv=fsync status=none
    # Wipe last 10MiB of disk
    dd if=/dev/zero of="$DEVICE" bs="$SECTOR" count="$MIB_TO_SECTORS" seek="$((SECTORS - MIB_TO_SECTORS))" conv=fsync status=none
    echo "Flashing..."
}

echo "Found ${FILENAME}..."

# Check the extension of the image file and run appropriate command
if [[ "$FILENAME" == *.zst ]]; then
    wipe_filesystem
    zstdcat "$FILENAME" | dd of="$DEVICE" bs=32M status=progress conv=fsync oflag=direct iflag=fullblock
elif [[ "$FILENAME" == *.iso || "$FILENAME" == *.img ]]; then
    wipe_filesystem
    dd if="$FILENAME" of="$DEVICE" bs=32M status=progress conv=fsync oflag=direct iflag=fullblock
else
    echo "Unsupported file format"
    exit 1
fi
