#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# make-disk-from-template.sh
#
# Build a GPT disk image from ESP + ROOT images using the layout implied by the
# provided Tegra-style partition template:
#   - Reserve 10MiB at the front (MBR + primary_gpt: 512 + 19968 sectors)
#   - Place ESP near the beginning (after the reservation)
#   - Place APP (rootfs) ALIGNED to 8MiB and AT THE END of the disk
#   - Partition numbers: APP = #1, ESP = #2
#   - Ensure rootfs has /nix/var/nix/profiles/system -> /nix/store/<hash>-nixos-system-… (Option 2)
#   - Keep ESP loader entries in sync with the root's closure path

#
# Usage:
#   ./make-disk-from-template.sh --esp esp.img[.zst] --root root.img[.zst] --out disk.img.zst
#
# Options:
#   --sector-size 512         # logical sector size; keep 512 unless you know otherwise
#   --esp-name esp            # GPT name for ESP
#   --app-name APP            # GPT name for root
#   --esp-type EF00           # GPT type for ESP (default EF00)
#   --app-type 8300           # GPT type for root (default 8300)
#   --app-guid <UUID>         # Optional fixed PARTITION GUID for APP (root)
#   --keep-raw                # Keep uncompressed raw disk.img alongside output
#   --no-sync-esp           # do not rewrite ESP loader entries
#   --no-fix-root-profile   # do not create/repair /nix/var/nix/profiles/system
#
# Notes:
# - We accept .zst or plain .img inputs for ESP/ROOT.
# - The script computes LBAs and writes payloads with 'dd' at exact offsets.
# - Backup GPT area is assumed to be 33 sectors (32 for table + 1 header).
#
# Template-derived constants:
#   HEAD_GAP_SECTORS = 512 (MBR) + 19968 (primary_gpt) = 20480 = 10MiB @ 512B sectors
#   APP_ALIGN_SECTORS = 16384 (8MiB alignment)
#   BACKUP_GPT_SECTORS = 33 (typical for 128 entries GPT; 32 table + 1 header)

SECTOR_SIZE=512
ESP_NAME="esp"
APP_NAME="APP"
ESP_TYPE="EF00"
APP_TYPE="b921b045-1df0-41c3-af44-4c6f280d3fae" # This is root type
#APP_TYPE="8300" This was linux-filesystem
APP_GUID="b921b045-1df0-41c3-af44-4c6f280d3fae"
KEEP_RAW=0
SYNC_ESP_TO_ROOT=1
FIX_ROOT_PROFILE=1

ESP_IN=""
ROOT_IN=""
OUT_ZST=""

usage() {
  cat <<"USAGE"
Usage:
  ./makediskimage.sh --esp esp.img[.zst] --root root.img[.zst] --out disk.img.zst

Options:
  --sector-size 512
  --esp-name esp
  --app-name APP
  --esp-type EF00
  --app-type 8300
  --app-guid <UUID>
  --keep-raw
  --no-sync-esp
  --no-fix-root-profile
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
  --no-sync-esp)
    SYNC_ESP_TO_ROOT=0
    shift 1
    ;;
  --no-fix-root-profile)
    FIX_ROOT_PROFILE=0
    shift 1
    ;;
  -h | --help)
    sed -n '1,200p' "$0"
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    exit 1
    ;;
  esac
done

if [[ -z ${ESP_IN} || -z ${ROOT_IN} || -z ${OUT_ZST} ]]; then
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
WORKDIR="$(mktemp -d -t diskxml-XXXXXX)"
mtesp="$WORKDIR/mtesp"
mtroot="$WORKDIR/mtroot"
mkdir -p "$mtesp" "$mtroot"

# --- Detect filesystem metadata from images (works with blkid -p) ---
get_img_label() { blkid -p -s LABEL -o value "$1" 2>/dev/null || true; }
get_img_type() { blkid -p -s TYPE -o value "$1" 2>/dev/null || true; }

cleanup() {
  # Best-effort unmounts
  mountpoint -q "$mtroot" && umount "$mtroot" || true
  mountpoint -q "$mtesp" && umount "$mtesp" || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

decompress_if_needed() {
  local in="$1" out="$2"
  if [[ $in == *.zst ]]; then
    unzstd -f -o "$out" "$in"
  else
    cp -f "$in" "$out"
  fi
}

ESP_IMG="$WORKDIR/esp.img"
ROOT_IMG="$WORKDIR/root.img"
DISK_IMG="$WORKDIR/disk.img"

echo "==> Preparing inputs in: $WORKDIR"
decompress_if_needed "$ESP_IN" "$ESP_IMG"
decompress_if_needed "$ROOT_IN" "$ROOT_IMG"

# Add slack to root image.
ROOT_SLACK_MIB="${ROOT_SLACK_MIB:-512}"
if [[ $ROOT_SLACK_MIB -gt 0 ]]; then
  echo "==> Adding ${ROOT_SLACK_MIB} MiB slack to root.img"
  SLACK_BYTES=$((ROOT_SLACK_MIB * 1024 * 1024))
  CURRENT_SIZE=$(stat -c%s "$ROOT_IMG")
  NEW_SIZE=$((CURRENT_SIZE + SLACK_BYTES))
  truncate -s "$NEW_SIZE" "$ROOT_IMG"
fi

# ---------- Helpers ----------
bytes_to_sectors() {
  local bytes="$1"
  local sect="$2"
  echo $(((bytes + sect - 1) / sect))
}
floor_align() {
  local v="$1" a="$2"
  echo $(((v / a) * a))
}
ceil_align() {
  local v="$1" a="$2"
  echo $((((v + a - 1) / a) * a))
}
to_mib() { echo $((($1 * SECTOR_SIZE) / 1024 / 1024)); }

extract_init_store_from_esp() {
  # Echoes the store dir (e.g., /nix/store/<hash>-nixos-system-... ) found in loader entries, or empty.
  shopt -s nullglob
  local conf
  for conf in "$mtesp"/loader/entries/*.conf; do
    # Grep for "init=/nix/store/xxx/init" and extract the store path part
    local line
    line="$(grep -Eo 'init=/nix/store/[^ ]+/init' "$conf" || true)"
    if [[ -n $line ]]; then
      tmp="${line#init=}"
      echo "${tmp%/init}"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  echo ""
}

find_root_nixos_system_in_store() {
  # Scan /nix/store for nixos-system-* which has an 'init' file
  shopt -s nullglob
  local candidates=("$mtroot"/nix/store/*-nixos-system-*)
  local c
  for c in "${candidates[@]}"; do
    [[ -e "$c/init" ]] && echo "${c#"$mtroot"}" && shopt -u nullglob && return 0
  done
  shopt -u nullglob
  echo ""
}

# ---------- NEW: repair /nix/var/nix/profiles/system in root, and sync ESP ----------
ensure_root_profile_and_sync() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "NOTE: Not root – skipping root profile fix and ESP sync (requires loop mounts)."
    return 0
  fi

  # Mount ESP (ro is enough for read; we may later write if we need to sync)
  mount -o loop,ro "$ESP_IMG" "$mtesp"

  # Mount root rw to allow creating the symlink
  if ! mount -o loop,rw "$ROOT_IMG" "$mtroot"; then
    echo "WARN: Could not mount root image rw; trying ro (will skip profile fix)."
    mount -o loop,ro "$ROOT_IMG" "$mtroot"
  fi

  local desired
  desired="$(extract_init_store_from_esp)"

  # Validate desired path exists in root; if not, try to detect from root store
  if [[ -n $desired && -e "$mtroot$desired/init" ]]; then
    echo "==> ESP expects system closure: $desired (exists in root)"
  else
    echo "WARN: ESP init path not found in root (or missing). Scanning root store…"
    local detected
    detected="$(find_root_nixos_system_in_store)"
    if [[ -z $detected ]]; then
      echo "ERROR: Could not find a nixos-system-* closure in root image."
      echo "       Root image likely incomplete; cannot create /nix/var/nix/profiles/system."
      # We still leave mounts for cleanup by trap
      return 0
    fi
    echo "==> Using root store system closure: $detected"
    desired="$detected"

    # If allowed, sync ESP entries to match this closure
    if ((SYNC_ESP_TO_ROOT)); then
      echo "==> Updating ESP loader entries to: $desired"
      mount -o remount,rw "$mtesp" || true
      shopt -s nullglob
      local cfg
      for cfg in "$mtesp"/loader/entries/*.conf; do
        # init=
        if grep -qE '(^|\s)init=/nix/store/[^ ]+/init(\s|$)' "$cfg"; then
          sed -i -E "s#(^|\\s)init=/nix/store/[^ ]+/init(\\s|$)# init=${desired}/init #g" "$cfg"
        fi
        # systemConfig=
        if grep -qE '(^|\s)systemConfig=/nix/store/[^ ]+(\s|$)' "$cfg"; then
          sed -i -E "s#(^|\\s)systemConfig=/nix/store/[^ ]+(\\s|$)# systemConfig=${desired} #g" "$cfg"
        fi
      done
      shopt -u nullglob
      sync || true
    else
      echo "NOTE: --no-sync-esp set; not updating ESP entries."
    fi
  fi

  # Create/repair /nix/var/nix/profiles/system symlink in root
  if ((FIX_ROOT_PROFILE)); then
    if mount | grep -q "on $mtroot type"; then
      if ! mount | grep -q "on $mtroot type .* (rw"; then
        echo "NOTE: Root mount is read-only; cannot create profile symlink. Skipping."
      else
        echo "==> Ensuring root profile symlink -> $desired"
        mkdir -p "$mtroot/nix/var/nix/profiles"
        # If exists and is different, replace
        if [[ -L "$mtroot/nix/var/nix/profiles/system" ]]; then
          local current
          current="$(readlink "$mtroot/nix/var/nix/profiles/system" || true)"
          if [[ $current != "$desired" ]]; then
            rm -f "$mtroot/nix/var/nix/profiles/system"
            ln -s "$desired" "$mtroot/nix/var/nix/profiles/system"
          fi
        else
          rm -f "$mtroot/nix/var/nix/profiles/system" 2>/dev/null || true
          ln -s "$desired" "$mtroot/nix/var/nix/profiles/system"
        fi
        sync || true
      fi
    fi
  else
    echo "NOTE: --no-fix-root-profile set; not creating system profile symlink."
  fi

  # Unmount; trap will recheck anyway
  umount "$mtroot" || true
  umount "$mtesp" || true
}

# Prefer reading the system closure from /nix/var/nix/profiles/system.
# Fallback to ESP init=, then scan nix store for *-nixos-system-* containing etc/.
resolve_system_closure_in_root() {
  local mroot="$1" mesp="$2" # mount points for root and esp
  local sys=""

  # From profile (best)
  if [[ -e "$mroot/nix/var/nix/profiles/system" ]]; then
    sys="$(readlink -f "$mroot/nix/var/nix/profiles/system" || true)"
    [[ -n $sys ]] && sys="${sys#"$mroot"}"
    if [[ -n $sys && -d "$mroot$sys/etc" ]]; then
      echo "$sys"
      return 0
    fi
  fi

  # From ESP init=
  if [[ -d "$mesp/loader/entries" ]]; then
    local from_esp
    from_esp="$(grep -R -Eo 'init=/nix/store/[^ ]+/init' "$mesp"/loader/entries/*.conf 2>/dev/null |
      sed 's#^.*init=##; s#/init$##' | head -n1 || true)"
    if [[ -n $from_esp && -d "$mroot${from_esp}/etc" ]]; then
      echo "$from_esp"
      return 0
    fi
  fi

  # Scan /nix/store for a *-nixos-system-* that includes an etc/ dir
  local c
  for c in "$mroot"/nix/store/*-nixos-system-*; do
    [[ -d "$c/etc" ]] || continue
    echo "${c#"$mroot"}"
    return 0
  done

  echo ""
  return 1
}

# Given a system closure (e.g., /nix/store/<hash>-nixos-system-...),
# resolve the target "/nix/store/<HASH>-etc/etc" to link /etc/static against.
resolve_hash_etc_target() {
  local mroot="$1" sys="$2"

  # Case 1: $sys/etc is a symlink into /nix/store/*-etc/etc → use that exact derivation.
  if [[ -L "$mroot$sys/etc" ]]; then
    local resolved
    resolved="$(readlink -f "$mroot$sys/etc" || true)"
    if [[ $resolved == "$mroot"/nix/store/*-etc/etc && -d $resolved ]]; then
      echo "${resolved#"$mroot"}"
      return 0
    fi
  fi

  # Case 2: $sys/etc is a directory but not symlink; try scan for the most plausible *-etc
  # (Prefer ones referenced by $sys/boot.json if present)
  if [[ -f "$mroot$sys/boot.json" ]]; then
    local cand
    cand="$(grep -Eo '"/nix/store/[^"]+-etc(/etc)?"' "$mroot$sys/boot.json" |
      tr -d '"' | sed 's#/etc$##' | head -n1 || true)"
    if [[ -n $cand && -d "$mroot${cand}/etc" ]]; then
      echo "$cand/etc"
      return 0
    fi
  fi

  # Case 3: scan nix store for *-etc containing etc/
  local e
  for e in "$mroot"/nix/store/*-etc; do
    [[ -d "$e/etc" ]] || continue
    echo "${e#"$mroot"}/etc"
    return 0
  done

  echo ""
  return 1
}

# Ensure: /etc/static -> /nix/store/<HASH>-etc/etc (inside root.img)
ensure_etc_static_symlink() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "NOTE: Not root — skipping /etc/static symlink fix (requires loop mounts)."
    return 0
  fi

  local mroot="$WORKDIR/mt_static_root"
  local mesp="$WORKDIR/mt_static_esp"
  mkdir -p "$mroot" "$mesp"

  # Mount images
  if ! mount -o loop,rw "$ROOT_IMG" "$mroot"; then
    echo "ERROR: cannot mount root image RW to fix /etc/static; aborting."
    umount "$mroot" 2>/dev/null || true
    exit 1
  fi
  if ! mount -o loop,ro "$ESP_IMG" "$mesp" 2>/dev/null; then
    # ESP mount is optional for this step; continue without it
    :
  fi

  # Resolve system closure
  local sys
  sys="$(resolve_system_closure_in_root "$mroot" "$mesp" || true)"
  if [[ -z $sys ]]; then
    echo "ERROR: No system closure with etc/ found in root image."
    umount "$mesp" 2>/dev/null || true
    umount "$mroot" 2>/dev/null || true
    exit 1
  fi

  # Resolve the exact *-etc target
  local etc_target
  etc_target="$(resolve_hash_etc_target "$mroot" "$sys" || true)"
  if [[ -z $etc_target || ! -d "$mroot$etc_target" ]]; then
    echo "ERROR: Could not locate /nix/store/<HASH>-etc/etc for system closure: $sys"
    umount "$mesp" 2>/dev/null || true
    umount "$mroot" 2>/dev/null || true
    exit 1
  fi

  # Create/repair /etc/static -> /nix/store/<HASH>-etc/etc
  mkdir -p "$mroot/etc"
  if [[ -L "$mroot/etc/static" ]]; then
    local cur
    cur="$(readlink "$mroot/etc/static" || true)"
    if [[ $cur != "$etc_target" ]]; then
      rm -f "$mroot/etc/static"
      ln -s "$etc_target" "$mroot/etc/static"
      echo "==> Re-linked /etc/static -> $etc_target"
    else
      echo "==> /etc/static already points to $etc_target"
    fi
  else
    rm -rf "$mroot/etc/static"
    ln -s "$etc_target" "$mroot/etc/static"
    echo "==> Linked /etc/static -> $etc_target"
  fi

  sync || true
  umount "$mesp" 2>/dev/null || true
  umount "$mroot" 2>/dev/null || true
}

# Run the new step before assembling the final disk
ensure_root_profile_and_sync

# Create /etc/static links
ensure_etc_static_symlink

# ---------- Layout math ----------
ESP_SIZE_BYTES=$(stat -c%s "$ESP_IMG")
ROOT_SIZE_BYTES=$(stat -c%s "$ROOT_IMG")

ESP_NSECT=$(bytes_to_sectors "$ESP_SIZE_BYTES" "$SECTOR_SIZE")
ROOT_NSECT=$(bytes_to_sectors "$ROOT_SIZE_BYTES" "$SECTOR_SIZE")

# Template-derived constants
HEAD_GAP_SECTORS=$((512 + 19968)) # 20480 sectors (10MiB @ 512B)
APP_ALIGN_SECTORS=16384           # 8MiB alignment
ESP_ALIGN_SECTORS=2048            # 1MiB alignment
BACKUP_GPT_SECTORS=33             # 1 header + 32 table sectors (128 entries)
MID_GAP_SECTORS=2048              # 1MiB nicety between ESP and APP

# ESP after the head reservation (aligned)
ESP_START_LBA=$(ceil_align "$HEAD_GAP_SECTORS" "$ESP_ALIGN_SECTORS")
ESP_END_LBA=$((ESP_START_LBA + ESP_NSECT - 1))

# Provisional disk size so APP can be aligned at end
BASE_MIN_END=$((ESP_END_LBA + MID_GAP_SECTORS + ROOT_NSECT + BACKUP_GPT_SECTORS))
DSECT=$(ceil_align "$BASE_MIN_END" "$APP_ALIGN_SECTORS")

compute_app_from_end() {
  local disk_last_lba=$((DSECT - 1))
  # Last usable LBA is before backup GPT area
  local app_last_usable=$((disk_last_lba - BACKUP_GPT_SECTORS))
  local app_end=$app_last_usable
  local app_start_unaligned=$((app_end - ROOT_NSECT + 1))
  local app_start
  app_start=$(floor_align "$app_start_unaligned" "$APP_ALIGN_SECTORS")
  echo "$app_start $app_end"
}

read -r APP_START_LBA APP_END_LBA < <(compute_app_from_end)

# Ensure APP does not overlap ESP + gap; grow disk if needed
while ((APP_START_LBA <= ESP_END_LBA + MID_GAP_SECTORS)); do
  DSECT=$((DSECT + APP_ALIGN_SECTORS))
  read -r APP_START_LBA APP_END_LBA < <(compute_app_from_end)
done

DISK_SIZE_BYTES=$((DSECT * SECTOR_SIZE))

echo "==> Computed layout (sector size = ${SECTOR_SIZE}B)"
printf "    Reserved head (MBR+primary_gpt): %d sectors (~%d MiB)\n" \
  "$HEAD_GAP_SECTORS" "$(to_mib "$HEAD_GAP_SECTORS")"
printf "    ESP : start=%-10d end=%-10d size=%-10d sectors (~%d MiB)\n" \
  "$ESP_START_LBA" "$ESP_END_LBA" "$ESP_NSECT" "$(to_mib "$ESP_NSECT")"
printf "    APP : start=%-10d end=%-10d size=%-10d sectors (~%d MiB) [aligned 8MiB]\n" \
  "$APP_START_LBA" "$APP_END_LBA" "$ROOT_NSECT" "$(to_mib "$ROOT_NSECT")"
printf "    Disk last LBA = %d  (backup GPT = %d sectors at end)\n" $((DSECT - 1)) "$BACKUP_GPT_SECTORS"
printf "    Disk size ≈ %d MiB\n" $((DISK_SIZE_BYTES / 1024 / 1024))

# ---------- Create disk, partition, write payloads ----------
echo "==> Creating sparse disk image"
truncate -s "$DISK_SIZE_BYTES" "$DISK_IMG"

echo "==> Creating GPT and partitions with sgdisk"
sgdisk --clear "$DISK_IMG" >/dev/null

# ESP must be #2; APP must be #1.
if [[ -n $APP_GUID ]]; then
  sgdisk \
    --new=1:"${ESP_START_LBA}":"${ESP_END_LBA}" \
    --typecode=1:"${ESP_TYPE}" \
    --change-name=1:"${ESP_NAME}" \
    --new=2:"${APP_START_LBA}":"${APP_END_LBA}" \
    --typecode=2:"${APP_TYPE}" \
    --change-name=2:"${APP_NAME}" \
    --partition-guid=1:"${APP_GUID}" \
    "$DISK_IMG" >/dev/null
else
  sgdisk \
    --new=1:"${ESP_START_LBA}":"${ESP_END_LBA}" \
    --typecode=1:"${ESP_TYPE}" \
    --change-name=1:"${ESP_NAME}" \
    --new=2:"${APP_START_LBA}":"${APP_END_LBA}" \
    --typecode=2:"${APP_TYPE}" \
    --change-name=2:"${APP_NAME}" \
    "$DISK_IMG" >/dev/null
fi

echo "==> Writing ESP payload -> partition #2 at LBA ${ESP_START_LBA}"
dd if="$ESP_IMG" of="$DISK_IMG" bs="$SECTOR_SIZE" seek="$ESP_START_LBA" conv=notrunc status=progress

echo "==> Writing APP (root) payload -> partition #1 at LBA ${APP_START_LBA}"
dd if="$ROOT_IMG" of="$DISK_IMG" bs="$SECTOR_SIZE" seek="$APP_START_LBA" conv=notrunc status=progress

echo "==> Partition table summary:"
sgdisk -p "$DISK_IMG" || true
echo
if command -v fdisk >/dev/null 2>&1; then
  echo "==> fdisk -l (for reference):"
  fdisk -l "$DISK_IMG" || true
fi

echo "==> Compressing disk -> $OUT_ZST"
zstd -T0 -f -o "$OUT_ZST" "$DISK_IMG"

if [[ $KEEP_RAW -eq 1 ]]; then
  RAW_OUT="$(dirname "$OUT_ZST")/$(basename "$OUT_ZST" .zst)"
  cp -f "$DISK_IMG" "$RAW_OUT"
  echo "==> Kept raw image at: $RAW_OUT"
fi

echo " Done. Output: $OUT_ZST"
