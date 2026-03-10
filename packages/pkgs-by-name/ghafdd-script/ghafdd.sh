#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

##############################################
# Prevent unbound variable errors with set -u
##############################################
MAKE_DISK_IMG_CMD=""
CUSTOM_RESULT_DIR=""
USB_DEVICE=""
KEEP_IMAGES=0

##############################################
# Root required
##############################################
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root. Needed for flashing usb."
  exit 1
fi

##############################################
# Parse CLI arguments
##############################################
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
  --makediskimage | -m)
    MAKE_DISK_IMG_CMD="$2"
    shift 2
    ;;
  --result-dir | -r)
    CUSTOM_RESULT_DIR="$2"
    shift 2
    ;;
  --help | -h)
    echo "Usage: ghafdd.sh [options]"
    echo "  --usb <device>           Flash directly to device (e.g. /dev/sdb)"
    echo "  --makediskimage <path>   Path to makediskimage.sh"
    echo "  --result-dir <path>      Path to result directory containing sd-image/"
    echo "  --keep-images            Keep merged disk image"
    echo "  --help                   Show this help message"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1"
    exit 1
    ;;
  esac
done

##############################################
# Locate makediskimage.sh (accept file or dir)
##############################################
if [[ -n $MAKE_DISK_IMG_CMD ]]; then
  # Normalize: if a directory is supplied, append 'makediskimage.sh'
  if [[ -d $MAKE_DISK_IMG_CMD ]]; then
    CANDIDATE="$MAKE_DISK_IMG_CMD/makediskimage.sh"
  else
    CANDIDATE="$MAKE_DISK_IMG_CMD"
  fi

  if [[ ! -f $CANDIDATE ]]; then
    echo "ERROR: makediskimage.sh not found at: $CANDIDATE"
    echo "Hint: pass the script file or a directory containing makediskimage.sh"
    exit 1
  fi
  if [[ ! -x $CANDIDATE ]]; then
    echo "ERROR: makediskimage.sh is not executable: $CANDIDATE"
    echo "Fix with: chmod +x \"$CANDIDATE\""
    exit 1
  fi

  MAKE_DISK_IMG_CMD="$CANDIDATE"
  echo "Using user-specified makediskimage.sh: $MAKE_DISK_IMG_CMD"
else
  # Automatic discovery (unchanged)
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

##############################################
# Build SEARCH_DIRS (custom dir first)
##############################################
SEARCH_DIRS=()

if [[ -n $CUSTOM_RESULT_DIR ]]; then
  if [[ ! -d $CUSTOM_RESULT_DIR ]]; then
    echo "ERROR: Provided --result-dir does not exist: $CUSTOM_RESULT_DIR"
    exit 1
  fi
  SEARCH_DIRS+=("$CUSTOM_RESULT_DIR")
fi

SEARCH_DIRS+=("./result" "../../../result")

##############################################
# Resolve image to flash
##############################################
FILE=""
echo "Checking if the image file exists..."

#
# 1. Try sd-image/*.zst
#
for dir in "${SEARCH_DIRS[@]}"; do
  if [[ -d "$dir/sd-image" ]]; then
    shopt -s nullglob
    files=("$dir"/sd-image/*.zst)
    shopt -u nullglob

    if ((${#files[@]} > 0)); then
      FILE=$(printf '%s\n' "${files[@]}" |
        while IFS= read -r f; do
          printf '%s %s\n' "$(stat -c %Y "$f")" "$f"
        done |
        sort -nr |
        awk 'NR==1 {print $2}')

      echo "Found sd-image: $FILE"
      continue_processing="yes"
      break
    fi
  fi
done

#
# 2. If not found, try merging ESP + ROOT
#
if [[ -z ${FILE:-} ]]; then
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

#
# 3. If still nothing: fail
#
if [[ -z ${continue_processing:-} ]]; then
  echo "Image files not found!!!"
  echo "I looked for:"
  echo "  sd-image/*.zst OR esp.img.zst + root.img.zst"
  echo "in these dirs:"
  printf '  %s\n' "${SEARCH_DIRS[@]}"
  exit 1
fi

echo "Detected the image file: $FILE"

##############################################
# Pre‑flight size info
##############################################
echo "Checking the required minimum size for USB drive (streaming test)…"
zstd -l "$FILE" | awk 'NR==2 {print $(NF-4), $(NF-3)}'

##############################################
# USB selection
##############################################

if [[ -n $USB_DEVICE ]]; then
  if [[ ! -b $USB_DEVICE ]]; then
    echo "ERROR: $USB_DEVICE is not a valid block device!"
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 1
  fi
  DRIVE="$USB_DEVICE"
  DRIVE_NAME="${DRIVE##*/}"
else
  echo
  echo "Please insert a USB drive to flash the Ghaf image and press any key to continue…"
  read -rsn1

  DRIVED="$(dmesg | grep -o 'sd[a-z]' | tail -n1 || true)"

  LSBLK_CANDIDATES="$(lsblk -d -n -b -o NAME,SIZE,RO,TRAN 2>/dev/null | awk '$3=="0" && $2!="0" {print $1,$4}')"

  DRIVE_NAME=""

  while read -r name tran; do
    if [[ ${tran:-} == "usb" ]]; then
      DRIVE_NAME="$name"
      break
    fi
  done <<<"$LSBLK_CANDIDATES"

  if [[ -z $DRIVE_NAME && -n $DRIVED ]]; then
    while read -r name tran; do
      if [[ $name == "$DRIVED" ]]; then
        DRIVE_NAME="$name"
        break
      fi
    done <<<"$LSBLK_CANDIDATES"
  fi

  if [[ -z $DRIVE_NAME && -n $DRIVED ]]; then
    DRIVE_NAME="$DRIVED"
  fi

  if [[ -z $DRIVE_NAME ]]; then
    echo "USB not detected automatically."
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM
    read -rp "Type the device name to use (e.g., sdb): " DRIVE_NAME
  fi

  DRIVE="/dev/${DRIVE_NAME}"
fi

DEVICE1="${DRIVE}1"
DEVICE2="${DRIVE}2"

if [[ ! -b $DRIVE ]]; then
  echo "USB not detected: $DRIVE"
  exit 2
fi

echo "The USB drive is ${DRIVE}"

##############################################
# Unmount any mounted partitions
##############################################
echo "Checking if the USB partitions are mounted — will unmount if needed."

while findmnt "$DEVICE1" >/dev/null 2>&1; do
  umount "$DEVICE1" >/dev/null 2>&1 || true
done
echo "Device ${DEVICE1} is safe."

while findmnt "$DEVICE2" >/dev/null 2>&1; do
  umount "$DEVICE2" >/dev/null 2>&1 || true
done
echo "Device ${DEVICE2} is safe."

##############################################
# Flash the drive
##############################################
echo "Writing the image to USB (this may take a while)…"

zstdcat -v "$FILE" | pv -b >"$DRIVE"

sync
echo "Successfully written image to ${DRIVE}"

if [[ $KEEP_IMAGES -eq 0 ]]; then
  rm -f ./disk.img ./disk.img.zst || true
else
  echo "Keeping merged disk image (--keep-images)."
fi

exit 0
