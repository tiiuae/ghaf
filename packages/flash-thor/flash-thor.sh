# shellcheck disable=SC2148
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

echo "============================================================"
echo "Ghaf Thor Flash Script (with NVMe support)"
echo "============================================================"
echo ""

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Working directory: $WORKDIR"
echo ""

img="${SD_IMAGE}/sd-image/${IMAGE_NAME}"
echo "Decompressing disk image..."
echo "  Source: $img"
pzstd -d "$img" -o "$WORKDIR/disk.img"
echo "  Decompressed size: $(stat -c%s "$WORKDIR/disk.img") bytes"
echo ""

EXISTING_DEVICES=""
for dev in /dev/sd[a-z]; do
  [ -b "$dev" ] && EXISTING_DEVICES="$EXISTING_DEVICES $dev"
done

echo "============================================================"
echo "Starting QSPI flash..."
echo "============================================================"
echo ""

FLASH_SCRIPT=$(find "${JETPACK_FLASH_SCRIPT}/bin" -type f -executable | head -1 || true)
if "$FLASH_SCRIPT"; then
  echo ""
  echo "QSPI flash reported success."
  echo "Device is now setting up NVMe USB gadget..."
else
  echo ""
  echo "ERROR: QSPI flash failed."
  echo "Check device connection and try again."
  exit 1
fi

echo ""
echo -n "Waiting for Thor NVMe to appear as USB storage..."

NEW_DEVICE=""
SECONDS=0

while [[ $SECONDS -lt 300 ]]; do
  sleep 2

  for dev in /dev/sd[a-z]; do
    [ -b "$dev" ] || continue
    if [[ " $EXISTING_DEVICES " != *" $dev "* ]]; then
      SIZE=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
      SIZE_GB=$((SIZE / 1000000000))
      SERIAL=$(lsblk -no SERIAL "$dev" 2>/dev/null || true)

      echo ""
      echo "New block device detected: $dev"
      echo "  Size: $SIZE bytes (~$SIZE_GB GB)"
      echo "  Serial: $SERIAL"

      # Auto-detection
      if [[ $SERIAL == "GHAF-THOR-NVME" ]]; then
        echo "  -> Auto-detected Thor NVMe!"
        NEW_DEVICE="$dev"
        break 2
      fi

      # Fallback to manual confirmation
      if command -v lsblk &>/dev/null; then
        echo "  Details:"
        lsblk -o NAME,SIZE,MODEL,SERIAL "$dev" 2>/dev/null | sed 's/^/    /'
      fi

      echo ""
      read -r -p "Is this the Thor NVMe device? [y/N] " confirm
      if [[ $confirm =~ ^[Yy]$ ]]; then
        NEW_DEVICE="$dev"
        break 2
      else
        echo "Skipping $dev, continuing to wait..."
        EXISTING_DEVICES="$EXISTING_DEVICES $dev"
      fi
    fi
  done

  printf "."
done

if [[ -z $NEW_DEVICE ]]; then
  echo ""
  echo "ERROR: Timeout waiting for USB storage device."
  exit 1
fi

echo ""
echo "Using device: $NEW_DEVICE"
for part in "$NEW_DEVICE"*; do
  if mount | grep -q "^$part "; then
    echo "  Unmounting $part..."
    umount "$part" 2>/dev/null || umount -l "$part" 2>/dev/null || true
  fi
done
sync
sleep 1

echo ""
echo "Clearing existing partition tables..."
sgdisk --zap-all "$NEW_DEVICE"

echo "Writing disk image to $NEW_DEVICE..."
dd if="$WORKDIR/disk.img" of="$NEW_DEVICE" bs=32M status=progress oflag=sync
sync

echo "Waiting for partition table to be recognized..."
partprobe "$NEW_DEVICE" 2>/dev/null || true
sleep 2

echo "Verifying root filesystem..."
PART2="${NEW_DEVICE}2"
for _ in $(seq 1 10); do
  [[ -b $PART2 ]] && break
  sleep 1
done
if [[ -b $PART2 ]]; then
  if fsck.ext4 -n "$PART2" 2>&1; then
    echo "Root filesystem OK."
  else
    echo "Root filesystem has errors. Please try again."
    exit 1
  fi
else
  echo "Could not find root partition. Exiting."
  exit 1
fi

PART1="${NEW_DEVICE}1"

echo "Writing completion marker to ESP..."
for _ in $(seq 1 30); do
  [[ -b $PART1 ]] && break
  sleep 1
done

if [[ -b $PART1 ]]; then
  mkdir -p "$WORKDIR/esp_mount"
  if mount "$PART1" "$WORKDIR/esp_mount" 2>/dev/null; then
    touch "$WORKDIR/esp_mount/.flash_complete"
    umount "$WORKDIR/esp_mount"
  else
    echo "WARN: Could not mount ESP to write marker"
  fi
else
  echo "WARN: ESP partition not found, skipping marker"
fi
sync

echo ""
echo "============================================================"
echo "Flash completed successfully."
echo "============================================================"
echo ""
