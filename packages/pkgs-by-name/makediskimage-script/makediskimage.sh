#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# makediskimage.sh (cleaned)
# -------------------------
# Merge an ESP image and a ROOT (ext4) image into a single GPT disk image.
# Assumptions now that ESP/ROOT are fixed:
#   - Root image already contains the full NixOS closure.
#   - make-ext4-fs.nix placed /nix-path-registration into the root image.
#   - First boot will run postBootCommands to load the DB and set the system profile.
# Therefore we DO NOT touch the root image's Nix store, system profile, or ESP entries here.
# We only place the two partitions and write their payloads byte-for-byte.
#
# Usage:
#   ./makediskimage.sh --esp esp.img[.zst] --root root.img[.zst] --out flash.img.zst #     [--sector-size 512] [--esp-name FIRMWARE] [--app-name NIXOS_ROOT] #     [--esp-type EF00] [--app-type 8300] [--app-guid UUID] [--keep-raw] [--no-verify-esp]
#
# Notes:
#   * We still verify the ESP (optional) for basic sanity.
#   * We do not modify loader entries or create any GC roots.

SECTOR_SIZE=512
ESP_NAME="FIRMWARE"
APP_NAME="NIXOS_ROOT"
ESP_TYPE="EF00"
APP_TYPE="8300"
APP_GUID=""
KEEP_RAW=0
VERIFY_ESP=1
ESP_IN=""
ROOT_IN=""
OUT_ZST=""

usage() {
  cat <<'USAGE'
Usage:
  ./makediskimage.sh --esp esp.img[.zst] --root root.img[.zst] --out flash.img.zst
Options:
  --sector-size 512
  --esp-name FIRMWARE
  --app-name NIXOS_ROOT
  --esp-type EF00
  --app-type 8300
  --app-guid <UUID>
  --keep-raw
  --no-verify-esp
USAGE
}

# ---------- Arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
  --esp)
    ESP_IN="$2"
    shift 2
    ;;
  --root)
    ROOT_IN="$2"
    shift 2
    ;;
  --out)
    OUT_ZST="$2"
    shift 2
    ;;
  --sector-size)
    SECTOR_SIZE="$2"
    shift 2
    ;;
  --esp-name)
    ESP_NAME="$2"
    shift 2
    ;;
  --app-name)
    APP_NAME="$2"
    shift 2
    ;;
  --esp-type)
    ESP_TYPE="$2"
    shift 2
    ;;
  --app-type)
    APP_TYPE="$2"
    shift 2
    ;;
  --app-guid)
    APP_GUID="$2"
    shift 2
    ;;
  --keep-raw)
    KEEP_RAW=1
    shift 1
    ;;
  --no-verify-esp)
    VERIFY_ESP=0
    shift 1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    exit 1
    ;;
  esac
done

if [[ -z ${ESP_IN:-} || -z ${ROOT_IN:-} || -z ${OUT_ZST:-} ]]; then
  echo "Error: --esp, --root and --out are required." >&2
  usage
  exit 1
fi

# Ensure unzstd exists; fallback to 'zstd -d'
if ! command -v unzstd >/dev/null 2>&1; then
  unalias unzstd >/dev/null 2>&1 || true
  unzstd() { zstd -d "$@"; }
fi

# ---------- Workspace ----------
WORKDIR="$(mktemp -d -t makedisk-XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
ESP_IMG="$WORKDIR/esp.img"
ROOT_IMG="$WORKDIR/root.img"
DISK_IMG="$WORKDIR/disk.img"

# Decompress or copy inputs
if [[ ${ESP_IN} == *.zst ]]; then unzstd -f -o "$ESP_IMG" "$ESP_IN"; else cp -f "$ESP_IN" "$ESP_IMG"; fi
if [[ ${ROOT_IN} == *.zst ]]; then unzstd -f -o "$ROOT_IMG" "$ROOT_IN"; else cp -f "$ROOT_IN" "$ROOT_IMG"; fi

echo "==> Inputs prepared in: $WORKDIR"

# ---------- Optional: verify ESP image ----------
verify_esp_image() {
  local img="$1" mesp
  mesp="$(mktemp -d -t verify-esp-XXXXXX)"
  if command -v fsck.vfat >/dev/null 2>&1; then
    fsck.vfat -n "$img" || echo "WARN: fsck.vfat reported issues (continuing)"
  fi
  if ! mount -t vfat -o ro,loop "$img" "$mesp" 2>/dev/null; then
    echo "ERROR: ESP not mountable as FAT: $img"
    rmdir "$mesp"
    return 1
  fi
  if [[ ! -f "$mesp/EFI/BOOT/BOOTAA64.EFI" || ! -d "$mesp/loader/entries" ]]; then
    echo "ERROR: ESP missing BOOTAA64.EFI or loader/entries"
    umount "$mesp"
    rmdir "$mesp"
    return 1
  fi
  umount "$mesp"
  rmdir "$mesp"
  echo "OK: ESP verification passed."
}

if ((VERIFY_ESP)); then
  echo "==> Verifying ESP..."
  verify_esp_image "$ESP_IMG"
fi

# ---------- Layout math ----------
bytes_to_sectors() {
  local bytes="$1"
  local sect="$2"
  echo $(((bytes + sect - 1) / sect))
}
ceil_align() {
  local v="$1" a="$2"
  echo $((((v + a - 1) / a) * a))
}
# to_mib helpful for printing
to_mib() { echo $((($1 * SECTOR_SIZE) / 1024 / 1024)); }

# --- compute sizes in sectors ---
ESP_SIZE_BYTES=$(stat -c%s "$ESP_IMG")
ROOT_SIZE_BYTES=$(stat -c%s "$ROOT_IMG")
ESP_NSECT=$(((ESP_SIZE_BYTES + SECTOR_SIZE - 1) / SECTOR_SIZE))
ROOT_NSECT=$(((ROOT_SIZE_BYTES + SECTOR_SIZE - 1) / SECTOR_SIZE))

# --- constants ---
APP_ALIGN_SECTORS=16384 # 8MiB
MID_GAP_SECTORS=2048    # 1MiB between ESP and APP
BACKUP_GPT_SECTORS=33   # 1 header + 32 table sectors

# ESP starts at 1MiB (2048 sectors) like before
ESP_START_LBA=2048
ESP_END_LBA=$((ESP_START_LBA + ESP_NSECT - 1))

# Place APP *after* ESP + small gap, aligned to 8MiB boundary
APP_START_CAND=$((ESP_END_LBA + 1 + MID_GAP_SECTORS))
APP_START_LBA=$((((APP_START_CAND + APP_ALIGN_SECTORS - 1) / APP_ALIGN_SECTORS) * APP_ALIGN_SECTORS))
APP_END_LBA=$((APP_START_LBA + ROOT_NSECT - 1))

# Now size the disk so there is room for backup GPT after APP
LAST_LBA_NEEDED=$((APP_END_LBA + BACKUP_GPT_SECTORS))
# Round the total disk size up to next 8MiB boundary for good measure
DSECT_ALIGN=$APP_ALIGN_SECTORS
DSECT=$((((LAST_LBA_NEEDED + DSECT_ALIGN - 1) / DSECT_ALIGN) * DSECT_ALIGN))

DISK_SIZE_BYTES=$((DSECT * SECTOR_SIZE))

compute_app_from_end() {
  local disk_last_lba=$((DSECT - 1))
  local app_last_usable=$((disk_last_lba - BACKUP_GPT_SECTORS))
  local app_end=$app_last_usable
  local app_start_unaligned=$((app_end - ROOT_NSECT + 1))
  local app_start=$(((app_start_unaligned / APP_ALIGN_SECTORS) * APP_ALIGN_SECTORS))
  echo "$app_start $app_end"
}
read -r APP_START_LBA APP_END_LBA < <(compute_app_from_end)

# Grow disk if APP would overlap ESP+gap
while ((APP_START_LBA <= ESP_END_LBA + MID_GAP_SECTORS)); do
  DSECT=$((DSECT + APP_ALIGN_SECTORS))
  read -r APP_START_LBA APP_END_LBA < <(compute_app_from_end)
done

DISK_SIZE_BYTES=$((DSECT * SECTOR_SIZE))

echo "==> Computed layout (sector size=${SECTOR_SIZE}B)"
printf " ESP : start=%-10d end=%-10d size=%-10d sectors (~%d MiB)
" "$ESP_START_LBA" "$ESP_END_LBA" "$ESP_NSECT" "$(to_mib "$ESP_NSECT")"
printf " APP : start=%-10d end=%-10d size=%-10d sectors (~%d MiB) [aligned 8MiB]
" "$APP_START_LBA" "$APP_END_LBA" "$ROOT_NSECT" "$(to_mib "$ROOT_NSECT")"
printf " Disk last LBA = %d (backup GPT = %d sectors at end)
" $((DSECT - 1)) "$BACKUP_GPT_SECTORS"
printf " Disk size ≈ %d MiB
" $((DISK_SIZE_BYTES / 1024 / 1024))

# ---------- Create disk, partition, write payloads ----------
echo "==> Creating sparse disk image"
truncate -s "$DISK_SIZE_BYTES" "$DISK_IMG"

echo "==> Creating GPT and partitions with sgdisk"
sgdisk -Z "$DISK_IMG" >/dev/null
# Partition 1: ESP
sgdisk --new=1:${ESP_START_LBA}:${ESP_END_LBA} --typecode=1:"${ESP_TYPE}" --change-name=1:"${ESP_NAME}" "$DISK_IMG"
# Partition 2: APP (root)
if [[ -n ${APP_GUID:-} ]]; then
  sgdisk --new=2:"${APP_START_LBA}":"${APP_END_LBA}" --typecode=2:"${APP_TYPE}" --change-name=2:"${APP_NAME}" --partition-guid=2:"${APP_GUID}" "$DISK_IMG"
else
  sgdisk --new=2:"${APP_START_LBA}":"${APP_END_LBA}" --typecode=2:"${APP_TYPE}" --change-name=2:"${APP_NAME}" "$DISK_IMG"
fi

echo "==> Writing ESP payload -> partition #1 at LBA ${ESP_START_LBA}"
dd if="$ESP_IMG" of="$DISK_IMG" bs="$SECTOR_SIZE" seek="$ESP_START_LBA" conv=notrunc status=progress

echo "==> Writing APP (root) payload -> partition #2 at LBA ${APP_START_LBA}"
dd if="$ROOT_IMG" of="$DISK_IMG" bs="$SECTOR_SIZE" seek="$APP_START_LBA" conv=notrunc status=progress

# Optional: quick partition table summary
sgdisk -p "$DISK_IMG" || true
if command -v fdisk >/dev/null 2>&1; then
  fdisk -l "$DISK_IMG" || true
fi

# Compress output
zstd -T0 -f -o "$OUT_ZST" "$DISK_IMG"
if [[ $KEEP_RAW -eq 1 ]]; then
  RAW_OUT="$(dirname "$OUT_ZST")/$(basename "$OUT_ZST" .zst)"
  cp -f "$DISK_IMG" "$RAW_OUT"
  echo "==> Kept raw image at: $RAW_OUT"
fi

echo "Done. Output: $OUT_ZST"

# Optional: verify ESP inside merged disk image using kpartx (if present)
verify_merged_disk_esp() {
  local disk="$1" mp loopdev out p1
  mp="$(mktemp -d -t verify-esp-disk-XXXXXX)"
  if ! command -v kpartx >/dev/null 2>&1; then
    echo "WARN: kpartx not available; skipping post-merge ESP verification."
    rmdir "$mp"
    return 0
  fi
  out="$(kpartx -av "$disk" 2>/dev/null || true)"
  # Extract first mapped partition device name (p1)
  loopdev="$(echo "$out" | awk '/add map/ && /p1/ {print $3}' | head -n1)"
  if [[ -z $loopdev ]]; then
    echo "WARN: Could not map partitions; skipping post-merge ESP verification."
    rmdir "$mp"
    return 0
  fi
  p1="/dev/mapper/$loopdev"
  if ! mount -t vfat -o ro "$p1" "$mp" 2>/dev/null; then
    echo "ERROR: Merged ESP (p1) not mountable."
    kpartx -dv "$disk" >/dev/null 2>&1 || true
    rmdir "$mp"
    return 1
  fi
  if [[ ! -f "$mp/EFI/BOOT/BOOTAA64.EFI" || ! -d "$mp/loader/entries" ]]; then
    echo "ERROR: Merged ESP missing BOOTAA64.EFI or loader/entries"
    umount "$mp"
    kpartx -dv "$disk" >/dev/null 2>&1 || true
    rmdir "$mp"
    return 1
  fi
  umount "$mp"
  kpartx -dv "$disk" >/dev/null 2>&1 || true
  rmdir "$mp"
  echo "OK: Post-merge ESP verification passed."
}

if ((VERIFY_ESP)); then
  echo "==> Verifying ESP inside merged disk image..."
  verify_merged_disk_esp "$DISK_IMG" || {
    echo "ERROR: Post-merge ESP verification failed."
    exit 1
  }
fi
