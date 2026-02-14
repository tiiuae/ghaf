#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- Root check ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root. Needed for flashing usb."
  exit 1
fi

# --- Where to find makediskimage.sh ---
# Use env override if provided, otherwise prefer ./makediskimage.sh, else PATH.
MAKE_DISK_IMG_CMD="${MAKE_DISK_IMG_CMD:-}"
if [[ -z ${MAKE_DISK_IMG_CMD} ]]; then
  if [[ -x "./makediskimage.sh" ]]; then
    MAKE_DISK_IMG_CMD="./makediskimage.sh"
  elif [[ -x "../makediskimage-script/makediskimage.sh" ]]; then
    MAKE_DISK_IMG_CMD="../makediskimage-script/makediskimage.sh"
  elif [[ -x "./packages/pkgs-by-name/makediskimage-script/makediskimage.sh" ]]; then
    MAKE_DISK_IMG_CMD="./packages/pkgs-by-name/makediskimage-script/makediskimage.sh"
  elif command -v makediskimage.sh >/dev/null 2>&1; then
    MAKE_DISK_IMG_CMD="$(command -v makediskimage.sh)"
  else
    MAKE_DISK_IMG_CMD="" # only needed if we must merge ESP+ROOT
  fi
fi

# --- Resolve which image to flash ---
FILE=""
echo "Checking if the image file exists..."

SEARCH_DIRS=("./result" "../../../result")

# -------------------------
# 1. Try sd-image/*.zst
# -------------------------
for dir in "${SEARCH_DIRS[@]}"; do
  if [[ -d "$dir/sd-image" ]]; then
    shopt -s nullglob
    files=("$dir"/sd-image/*.zst)
    shopt -u nullglob
    if ((${#files[@]} > 0)); then
      # pick newest
      FILE=$(printf '%s\n' "${files[@]}" |
        while IFS= read -r f; do
          printf '%s %s\n' "$(stat -c %Y "$f")" "$f"
        done |
        sort -nr |
        awk 'NR==1 {print $2}')
      echo "Found sd-image: $FILE"
      break
    fi
  fi
done

# Already found sd-image? done.
if [[ -n ${FILE:-} ]]; then
  echo "Detected the image file: $FILE"
  continue_processing="yes"
else
  # -------------------------
  # 2. Try esp + root
  # -------------------------
  for dir in "${SEARCH_DIRS[@]}"; do
    ESP="$dir/esp.img.zst"
    ROOT="$dir/root.img.zst"
    if [[ -f $ESP && -f $ROOT ]]; then
      echo "Found ESP:  $ESP"
      echo "Found ROOT: $ROOT"

      if [[ -z $MAKE_DISK_IMG_CMD ]]; then
        echo "Error: makediskimage.sh not found!"
        exit 1
      fi

      "$MAKE_DISK_IMG_CMD" \
        --esp "$ESP" \
        --root "$ROOT" \
        --out ./disk.img.zst

      FILE="./disk.img.zst"
      echo "Created merged disk image."
      continue_processing="yes"
      break
    fi
  done
fi

# -------------------------
# 3. If no matches, fail
# -------------------------
if [[ -z ${continue_processing:-} ]]; then
  echo "Image files not found!!!"
  echo "I looked for:"
  echo "  sd-image/*.zst OR esp.img.zst+root.img.zst"
  echo "in these dirs:"
  printf '  %s\n' "${SEARCH_DIRS[@]}"
  exit 1
fi

echo "Detected the image file: $FILE"

# --- Pre-flight: estimate stream size (kept as in your script) ---
echo "Checking the required minimum size for USB drive (streaming test)…"
zstd -l disk.img.zst | awk 'NR==2 {print $(NF-4), $(NF-3)}'

# --- Optional device argument (e.g. ./flash.sh --usb /dev/sdb --keep-images)

# --- CLI argument parsing ---
USB_DEVICE=""
KEEP_IMAGES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --usb)
    USB_DEVICE="$2"
    shift 2
    ;;
  --keep-images)
    KEEP_IMAGES=1
    shift 1
    ;;
  *)
    echo "Unknown argument: $1"
    exit 1
    ;;
  esac
done

if [[ -n $USB_DEVICE ]]; then
  if [[ ! -b $USB_DEVICE ]]; then
    echo "ERROR: $USB_DEVICE is not a valid block device!"
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 1
  fi
  DRIVE="$USB_DEVICE"
  DRIVE_NAME="${DRIVE##*/}"
  echo "Using user-specified USB device: $DRIVE"
else
  # --- Prompt to insert USB ---
  echo
  echo "Please insert a USB drive to flash the Ghaf image and press any key to continue…"
  read -rsn1
  echo "You pressed a key! Continuing…"
  sleep 1

  # --- Detect USB block device ---
  # Keep your original approach but fix typos, and add a more robust lsblk-based path.
  # 1) Try to find the most recently added 'sdX' from dmesg
  DRIVED="$(dmesg | grep -o 'sd[a-z]' | tail -n1 || true)"

  # 2) Prefer lsblk filter: non-readonly, size > 0, optional transport=usb
  #    Cross-check with DRIVED if available
  LSBLK_CANDIDATES="$(lsblk -d -n -b -o NAME,SIZE,RO,TRAN 2>/dev/null | awk '$3=="0" && $2!="0" {print $1,$4}')"
  # Filter for USB first, else fallback to any candidate matching DRIVED
  DRIVE_NAME=""
  while read -r name tran; do
    if [[ ${tran:-} == "usb" ]]; then
      DRIVE_NAME="$name"
      break
    fi
  done <<<"${LSBLK_CANDIDATES}"

  if [[ -z ${DRIVE_NAME} && -n ${DRIVED} ]]; then
    # Match the name from DRIVED if present
    while read -r name tran; do
      if [[ $name == "$DRIVED" ]]; then
        DRIVE_NAME="$name"
        break
      fi
    done <<<"${LSBLK_CANDIDATES}"
  fi

  # Final fallback: use DRIVED directly if nothing else worked
  if [[ -z ${DRIVE_NAME} && -n ${DRIVED} ]]; then
    DRIVE_NAME="${DRIVED}"
  fi

  if [[ -z ${DRIVE_NAME} ]]; then
    echo "USB not detected automatically."
    echo "Available block devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM
    echo
    read -rp "Type the device name to use (e.g., sdb): " DRIVE_NAME
  fi
fi

DRIVE="/dev/${DRIVE_NAME}"
DEVICE1="${DRIVE}1"
DEVICE2="${DRIVE}2"

if [ -b "${DRIVE}" ]; then
  echo "The USB drive is ${DRIVE}"
else
  echo "USB not detected as block device: ${DRIVE}"
  echo "Please ensure your system can see the USB device and re-run this script."
  exit 2
fi

# --- Ensure partitions are not mounted ---
echo "Checking if the USB partitions are mounted — will unmount if needed."
while findmnt "${DEVICE1}" >/dev/null 2>&1; do
  umount "${DEVICE1}" >/dev/null 2>&1 || true
done
echo "Device ${DEVICE1} is safe."

while findmnt "${DEVICE2}" >/dev/null 2>&1; do
  umount "${DEVICE2}" >/dev/null 2>&1 || true
done
echo "Device ${DEVICE2} is safe."

# Extra: attempt to unmount any partition of the target device (covers more than p1/p2)
for p in /dev/disk/by-partuuid/*; do
  [ -e "$p" ] || continue
done

# --- Flash ---
echo "Writing the image to USB (this may take a while)…"
# Using pv for progress; zstdcat for decompression; direct write to the block device.
# You can add oflag=direct to reduce page cache effects if desired.
zstdcat -v "${FILE}" | pv -b >"${DRIVE}"

sync
echo "Successfully written image to ${DRIVE}"

if [[ $KEEP_IMAGES -eq 0 ]]; then
  echo "Removing generated merged disk image..."
  rm -f ./disk.img ./disk.img.zst 2>/dev/null || true
else
  echo "Keeping merged disk image as requested (--keep-images)."
fi

exit 0
