#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Default it here rather than demanding it here. ghaf.image_url= on the kernel
# command line is an equally valid source -- it is how netboot supplies it -- but
# it is not parsed until below, and `set -u` aborts on the bare reference long
# before that.
IMG_PATH="${IMG_PATH:-}"

help_msg() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Ghaf installation script

Options:
  -w            Wipe only
  -e            Install with disk encryption
  -s            Install with Secure Boot enrollment
  -d DEVICE     Target device, e.g. /dev/nvme0n1 (skips the device prompt)
  -y            Do not ask for confirmation before writing
  -h, --help    Show this help message and exit.

IMG_PATH may be a directory (ISO install) or an http(s) base URL (netboot);
in the URL case the image and its block map are fetched and streamed straight
to the disk without being staged anywhere.

Environment:
  GHAF_QUEUE_MAX_WAIT   seconds to wait for an install server's download slot
                        before giving up (default 14400). A fleet server
                        staggers image downloads, so a long wait is normal.

After a successful install the firmware is pointed at the disk that was just
written -- a boot entry is created if none exists, put first in BootOrder, and
BootNext is set. Failing to do so is a warning, never fatal.

Kernel parameters, for unattended netboot installs:
  ghaf.install_target=/dev/nvme0n1   as -d, implies -y, and reboots when done
  ghaf.install_encrypt               as -e
  ghaf.install_secureboot            as -s
  ghaf.install_noreboot              stay in the installer after an unattended
                                     install instead of rebooting into it

Examples:
  $(basename "$0") -w
  $(basename "$0") -e
  $(basename "$0") -s
  $(basename "$0") -e -s
  $(basename "$0") -d /dev/nvme0n1 -y

EOF
}

WIPE_ONLY=false
ENCRYPTED_INSTALL=false
SECUREBOOT_INSTALL=false
DEVICE_NAME=""
ASSUME_YES=false
# Set only by ghaf.install_target=, never by -d/-y. The distinction matters: -d
# is someone at a console who can reboot the machine themselves, whereas the
# kernel parameter means nobody is there and there is no installation medium to
# remove either -- so finishing with "please reboot" leaves the machine sitting
# in the installer forever.
UNATTENDED=false
REBOOT_WHEN_DONE=true

# Kernel-parameter defaults, so a netbooted lab machine can install unattended
# with no console interaction. Command-line flags still win over these.
#   ghaf.install_target=/dev/nvme0n1   pick the disk and skip both prompts
#   ghaf.install_encrypt               same as -e
#   ghaf.install_secureboot            same as -s
# Deliberately opt-in: with none of these the installer behaves exactly as it
# always has, because skipping the confirmation before a destructive write
# should never be the default.
if [ -r /proc/cmdline ]; then
  _cmdline=$(cat /proc/cmdline)
  case " $_cmdline " in
  *" ghaf.install_target="*)
    DEVICE_NAME=$(sed -n 's/.*[[:space:]]ghaf\.install_target=\([^[:space:]]*\).*/\1/p' /proc/cmdline)
    ASSUME_YES=true
    UNATTENDED=true
    ;;
  esac
  case " $_cmdline " in *" ghaf.install_encrypt "*) ENCRYPTED_INSTALL=true ;; esac
  case " $_cmdline " in *" ghaf.install_secureboot "*) SECUREBOOT_INSTALL=true ;; esac
  # Escape hatch for debugging a failed unattended install: without it the
  # evidence reboots away before anyone can look at it.
  case " $_cmdline " in *" ghaf.install_noreboot "*) REBOOT_WHEN_DONE=false ;; esac

  # ghaf.image_url= overrides IMG_PATH, and on netboot it is the ONLY correct
  # source. Without this the netboot installer inherits the ISO's baked-in
  # imageSource (/iso/ghaf-image), a path that does not exist when booted over
  # the network
  case " $_cmdline " in
  *" ghaf.image_url="*)
    IMG_PATH=$(sed -n 's/.*[[:space:]]ghaf\.image_url=\([^[:space:]]*\).*/\1/p' /proc/cmdline)
    ;;
  esac
fi

if [ -z "$IMG_PATH" ]; then
  echo "No image source: set IMG_PATH, or boot with ghaf.image_url=<url>."
  exit 1
fi

while getopts "wesyd:h" opt; do
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
  d)
    DEVICE_NAME="$OPTARG"
    ;;
  y)
    ASSUME_YES=true
    ;;
  h)
    help_msg
    exit 0
    ;;
  ?)
    help_msg
    exit 1
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
  # A device supplied by -d or ghaf.install_target= still goes through every
  # check below; it just cannot be re-prompted on failure, so a bad value is
  # fatal instead of looping forever against a console nobody is watching.
  if [ -n "$DEVICE_NAME" ]; then
    preset=true
  else
    preset=false
    read -r -p "Device name [e.g. /dev/nvme0n1]: " DEVICE_NAME
  fi

  reject() {
    echo "$1"
    if [ "$preset" = true ]; then
      echo "Refusing to continue with the preset target $DEVICE_NAME."
      exit 1
    fi
    DEVICE_NAME=""
  }

  # Input validation: ensure device name starts with /dev/ and contains no path traversal
  if [[ ! $DEVICE_NAME =~ ^/dev/[a-zA-Z0-9._-]+$ ]]; then
    reject "Invalid device name format. Device must be in /dev/ and contain only alphanumeric characters, dots, underscores, and dashes."
    continue
  fi

  # Additional security check: ensure the device exists as a block device
  if [ ! -b "$DEVICE_NAME" ]; then
    reject "Device is not a valid block device!"
    continue
  fi

  # Safely get basename to prevent directory traversal
  device_basename=$(basename "$DEVICE_NAME")
  if [ ! -d "/sys/block/$device_basename" ]; then
    reject "Device not found in sysfs!"
    continue
  fi

  # Check if removable
  if [ "$(cat "/sys/block/$device_basename/removable")" != "0" ]; then
    if [ "$ASSUME_YES" = true ]; then
      echo "Device $DEVICE_NAME is removable; continuing because -y was given."
      break
    fi
    read -r -p "Device provided is removable, do you want to continue? [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY])
      break
      ;;
    *)
      $preset && exit 1
      DEVICE_NAME=""
      continue
      ;;
    esac
  fi

  break
done

echo "Installing/Deleting Ghaf on $DEVICE_NAME"
if [ "$ASSUME_YES" = true ]; then
  echo "Proceeding without confirmation (-y / ghaf.install_target=)."
else
  read -r -p 'Do you want to continue? [y/N] ' response

  case "$response" in
  [yY][eE][sS] | [yY]) ;;
  *)
    echo "Exiting..."
    exit
    ;;
  esac
fi

# Resolve and validate the image source BEFORE anything destructive happens.
resolve_image_source() {
  # IMG_PATH is either a directory (booted from the ISO, which carries the image)
  # or an http(s) base URL (netboot, where the image is fetched now and was never
  # embedded).
  GHAF_BMAP=""
  if [[ $IMG_PATH =~ ^https?:// ]]; then
    GHAF_REMOTE=true
    if [[ $IMG_PATH == *.raw.zst ]]; then
      GHAF_RAW_SRC="$IMG_PATH"
    else
      GHAF_RAW_SRC="${IMG_PATH%/}/ghaf-image.raw.zst"
    fi

    # bmaptool needs the map as a seekable local file; it is ~50 KB. Fatal if
    # absent: its per-range sha256 checksums are the only integrity check on an
    # image pulled over plain HTTP, so an unverified dd would be worse than
    # stopping here.
    rundir="${GHAF_INSTALLER_RUNDIR:-/run/ghaf-installer}"
    mkdir -p "$rundir"
    GHAF_BMAP="$rundir/ghaf-image.bmap"
    if ! curl -fsSL --connect-timeout 10 --retry 5 --retry-delay 2 --retry-all-errors \
      -o "$GHAF_BMAP" "${GHAF_RAW_SRC%.raw.zst}.bmap"; then
      echo "Could not fetch block map ${GHAF_RAW_SRC%.raw.zst}.bmap"
      exit 1
    fi
  else
    GHAF_REMOTE=false
    shopt -s nullglob
    raw_file=("$IMG_PATH"/*.raw.zst)
    shopt -u nullglob

    if [ ${#raw_file[@]} -eq 0 ]; then
      echo "No .raw.zst image found in $IMG_PATH"
      exit 1
    fi
    GHAF_RAW_SRC="${raw_file[0]}"
    [ -s "${GHAF_RAW_SRC%.raw.zst}.bmap" ] && GHAF_BMAP="${GHAF_RAW_SRC%.raw.zst}.bmap"
  fi

}

# A wipe-only run needs no image, so do not make it depend on a reachable
# source -- that would turn `--wipe` into something that can fail for reasons
# entirely unrelated to wiping.
if [ "$WIPE_ONLY" != true ]; then
  resolve_image_source
fi

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

if [ "$WIPE_ONLY" != true ]; then
  # Before the wipe, while find_esp_device still has partitions. Empty is fine:
  # the lib falls back to the drive's serial.
  point_bootnext_at_disk "$DEVICE_NAME" "$(find_esp_device 2>/dev/null || true)"
fi

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

feed_image() {
  if [ "$GHAF_REMOTE" = true ]; then
    # Single-shot: no --retry here. See wait_for_image_slot above.
    curl -fL --no-progress-meter --connect-timeout 10 "$GHAF_RAW_SRC"
  else
    cat "$GHAF_RAW_SRC"
  fi | zstdcat -T0
}

if [ "$GHAF_REMOTE" = true ]; then
  wait_for_image_slot "$GHAF_RAW_SRC" || {
    echo "Could not get an image download slot from the install server."
    exit 1
  }
fi

# Prefer bmaptool: it skips unmapped ranges and verifies the per-range sha256
# from the map as it copies. The bare dd below stays as the fallback.
if [ -n "$GHAF_BMAP" ] && command -v bmaptool >/dev/null 2>&1 &&
  feed_image | bmaptool copy --bmap "$GHAF_BMAP" - "$DEVICE_NAME"; then
  echo "Image written and verified against the block map."
else
  [ -n "$GHAF_BMAP" ] && echo "bmaptool unavailable or failed; falling back to a plain streaming write."
  feed_image | dd of="$DEVICE_NAME" bs=32M status=progress
fi

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

  if ! ensure_efivars; then
    echo "EFI variables not available. Ensure the installer booted in UEFI mode."
    exit 1
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

# Before any reboot, and for attended installs too: an operator who installs
# from a USB stick on a machine that prefers network boot has the same problem.
udevadm settle
if esp_for_boot_entry="$(find_esp_device)"; then
  set_boot_to_disk "$DEVICE_NAME" "$esp_for_boot_entry"
else
  echo "WARNING: could not find the ESP; leaving boot order untouched." >&2
fi

if [ "$UNATTENDED" = true ] && [ "$REBOOT_WHEN_DONE" = true ]; then
  echo "Installation done. Rebooting into the installed system in 10 seconds."
  echo "(boot the machine with ghaf.install_noreboot to stay in the installer)"
  # set_boot_to_disk above is what makes this reboot land on the disk. Before it
  # existed, a netbooted machine -- which typically has network boot ahead of the
  # disk in its BootOrder -- came back into the installer unless the install
  # server had stopped, so shutting the server down was the only thing
  # preventing a reinstall loop. That is no longer load-bearing, which is what
  # lets one server serve a fleet.
  sleep 10
  systemctl reboot
else
  echo "Installation done. Please remove the installation media and reboot"
fi
