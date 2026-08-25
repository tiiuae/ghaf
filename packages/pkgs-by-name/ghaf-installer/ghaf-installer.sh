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

# Mount efivarfs if it is not already, and report whether EFI variables are
# usable at all. Two callers with opposite policies -- Secure Boot enrollment
# cannot proceed without them, set_boot_to_disk only warns -- so this reports
# rather than exits.
ensure_efivars() {
  [ -d /sys/firmware/efi/efivars ] || return 1
  mountpoint -q /sys/firmware/efi/efivars && return 0
  echo "Mounting efivarfs..." >&2
  mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null
}

# Which loader the firmware should be pointed at, read off the ESP rather than
# assumed. A pre-built image's ESP is written by disko inside a VM, so what it
# actually contains is a property of the image and not of this script -- and the
# removable fallback (\EFI\BOOT\BOOT*.EFI) may be the only thing present.
# Echoes an EFI-style backslash path, or nothing.
find_esp_loader() {
  local esp_device="$1" mnt loader=""
  mnt="$(mktemp -d)"
  if ! mount -t vfat -o ro "$esp_device" "$mnt" 2>/dev/null; then
    rmdir "$mnt"
    return 1
  fi
  # systemd-boot proper first: it is the entry the installed system goes on to
  # manage itself. The removable fallback boots the same binary but is the path
  # firmware uses for "any disk", so a machine with several disks could match
  # the wrong one.
  local candidate
  for candidate in \
    EFI/systemd/systemd-bootx64.efi \
    EFI/systemd/systemd-bootaa64.efi \
    EFI/BOOT/BOOTX64.EFI \
    EFI/BOOT/BOOTAA64.EFI; do
    if [ -e "$mnt/$candidate" ]; then
      loader="\\${candidate//\//\\}"
      break
    fi
  done
  umount "$mnt" 2>/dev/null || true
  rmdir "$mnt" 2>/dev/null || true
  [ -n "$loader" ] || return 1
  printf '%s\n' "$loader"
}

# Point the firmware at the disk we just wrote, so the machine boots the
# installed system rather than netbooting again.
#
# Until this existed, the ONLY thing stopping a netbooted machine reinstalling
# itself in a loop was the install server shutting down after one transfer
# (ghaf-netboot's --exit-after-serve). That cannot survive a server that stays
# up for a fleet, so the machine has to take responsibility for its own next
# boot instead.
#
# Both halves are deliberate:
#   efibootmgr -c   creates the entry AND puts it first in BootOrder -- durable,
#                   and works on a machine that has never had a Linux entry.
#   efibootmgr -n   BootNext, one-shot and self-clearing -- covers the one boot
#                   that matters even where firmware policy rewrites BootOrder.
#
# Every failure here is a warning, never fatal: a correctly written disk whose
# boot order could not be changed is still a correctly written disk, and exiting
# would discard a completed install over a recoverable problem.
set_boot_to_disk() {
  local esp_device part_num loader entries bootnum partuuid

  command -v efibootmgr >/dev/null 2>&1 || {
    echo "WARNING: efibootmgr not available; leaving boot order untouched." >&2
    return 0
  }

  ensure_efivars || {
    echo "WARNING: no EFI variables (legacy/CSM boot?); leaving boot order untouched." >&2
    return 0
  }

  udevadm settle
  esp_device="$(find_esp_device)" || {
    echo "WARNING: could not find the ESP; leaving boot order untouched." >&2
    return 0
  }

  # lsblk rather than stripping digits off the path: nvme0n1p1 and sda1 do not
  # share a suffix rule, and getting it wrong would aim -p at the wrong slot.
  part_num="$(lsblk -no PARTN "$esp_device" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$part_num" ] || {
    echo "WARNING: could not read the ESP partition number; leaving boot order untouched." >&2
    return 0
  }

  loader="$(find_esp_loader "$esp_device")" || {
    echo "WARNING: no EFI loader found on the ESP; leaving boot order untouched." >&2
    return 0
  }
  echo "Boot loader on the ESP: $loader"

  # `|| true` on every pipeline in this function is not defensive noise:
  # writeShellApplication runs the script under `set -euo pipefail`, so a grep
  # that matches nothing exits 1, pipefail promotes that to the pipeline's
  # status, and the assignment aborts the whole installer. "No matching boot
  # entry yet" is the NORMAL case on a machine that has never had one -- i.e.
  # exactly the case this function exists for.
  partuuid="$(lsblk -no PARTUUID "$esp_device" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)"

  # Reuse an existing entry rather than adding one per install. NVRAM is small
  # and a reinstalled machine would otherwise accumulate identical entries until
  # the firmware refuses to add more.
  entries="$(efibootmgr -v 2>/dev/null || true)"
  bootnum=""
  if [ -n "$partuuid" ]; then
    bootnum="$(
      printf '%s\n' "$entries" |
        grep -i -- "$partuuid" |
        grep -iF -- "$loader" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' |
        head -1 || true
    )"
  fi

  if [ -n "$bootnum" ]; then
    echo "Reusing existing boot entry Boot$bootnum"
    # -o puts it first without creating anything; -c would have done this as a
    # side effect, and an entry we are reusing still has to win.
    local order
    order="$(printf '%s\n' "$entries" | sed -n 's/^BootOrder: //p' | tr -d '[:space:]' || true)"
    if [ -n "$order" ] && [ "${order%%,*}" != "$bootnum" ]; then
      order="$bootnum,$(printf '%s' "$order" | tr ',' '\n' | grep -viF "$bootnum" | paste -sd, - || true)"
      efibootmgr -o "${order%,}" >/dev/null 2>&1 ||
        echo "WARNING: could not reorder BootOrder; BootNext below still applies." >&2
    fi
  else
    echo "Creating boot entry for $DEVICE_NAME partition $part_num"
    efibootmgr -c -d "$DEVICE_NAME" -p "$part_num" -L "Ghaf" -l "$loader" >/dev/null 2>&1 || {
      echo "WARNING: could not create a boot entry; leaving boot order untouched." >&2
      return 0
    }
    entries="$(efibootmgr -v 2>/dev/null || true)"
    bootnum="$(
      printf '%s\n' "$entries" |
        grep -iF -- "$loader" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*Ghaf.*/\1/p' |
        head -1 || true
    )"
    # efibootmgr -c puts what it created first in BootOrder, so its head is the
    # new entry when the label match above could not find it.
    [ -n "$bootnum" ] || bootnum="$(
      printf '%s\n' "$entries" | sed -n 's/^BootOrder: \([0-9A-Fa-f]\{4\}\).*/\1/p' || true
    )"
  fi

  if [ -n "$bootnum" ]; then
    efibootmgr -n "$bootnum" >/dev/null 2>&1 &&
      echo "BootNext set to Boot$bootnum (one-shot)" ||
      echo "WARNING: could not set BootNext." >&2
  else
    echo "WARNING: could not determine the new boot entry number." >&2
  fi

  # The only evidence anyone gets from an unattended fleet install.
  echo "--- efibootmgr ---"
  efibootmgr 2>/dev/null || true
  echo "------------------"
}

# Stop this machine netbooting again BEFORE the long part starts.
#
# On a fleet install the operator puts each machine into PXE by hand -- F12 --
# because it may be a Windows machine, or one nobody has credentials for, so
# nothing can ssh in and arm it. But by now our installer is running ON the
# machine, so it can do it itself, with no credentials and no network round
# trip.
#
# Timing is the point. The image download can sit in an install server's queue
# for hours; a machine power-cycled or crashed during that window, with network
# boot still ahead of its disk, comes straight back into the installer. Setting
# BootNext here costs nothing and closes that window. set_boot_to_disk runs
# again after the write, and that is the one that creates and orders the entry
# for the ESP this install produces -- this is only the guard for the gap
# between.
#
# Deliberately before the wipe: it points at an entry that already exists, and
# after the wipe there is nothing left to point at.
point_bootnext_at_disk() {
  local entries bootnum esp partuuid serial model

  command -v efibootmgr >/dev/null 2>&1 || return 0
  ensure_efivars || return 0

  entries="$(efibootmgr -v 2>/dev/null || true)"
  [ -n "$entries" ] || return 0

  # The ESP that is on the disk right now, if this machine was installed before.
  # Its PARTUUID appears in the firmware's own entry for it.
  bootnum=""
  esp="$(find_esp_device 2>/dev/null || true)"
  if [ -n "$esp" ]; then
    partuuid="$(lsblk -no PARTUUID "$esp" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)"
    if [ -n "$partuuid" ]; then
      bootnum="$(printf '%s\n' "$entries" | grep -i -- "$partuuid" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' | head -1 || true)"
    fi
  fi

  # Otherwise the firmware's auto-created entry, which names the drive: on a
  # Dell it reads "UEFI BG7 KIOXIA 1024GB 3GGPSDEUZ43B 1". The serial is the
  # discriminating part, and it is what tells this disk from a second one.
  if [ -z "$bootnum" ]; then
    serial="$(lsblk -dno SERIAL "$DEVICE_NAME" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -n "$serial" ]; then
      bootnum="$(printf '%s\n' "$entries" | grep -iF -- "$serial" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' | head -1 || true)"
    fi
  fi
  if [ -z "$bootnum" ]; then
    model="$(lsblk -dno MODEL "$DEVICE_NAME" 2>/dev/null | sed 's/[[:space:]]*$//' || true)"
    if [ -n "$model" ]; then
      bootnum="$(printf '%s\n' "$entries" | grep -iF -- "$model" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' | head -1 || true)"
    fi
  fi

  if [ -z "$bootnum" ]; then
    # A disk that has never been bootable has no entry to point at. Nothing is
    # wrong; set_boot_to_disk creates one once there is an ESP to name.
    echo "No existing boot entry for $DEVICE_NAME yet; will create one after the write."
    return 0
  fi

  if efibootmgr -n "$bootnum" >/dev/null 2>&1; then
    echo "BootNext set to Boot$bootnum ($DEVICE_NAME) before downloading."
  else
    echo "WARNING: could not set BootNext before downloading; continuing." >&2
  fi
}

if [ "$WIPE_ONLY" != true ]; then
  point_bootnext_at_disk
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

# How long to sit in an install server's queue before giving up, in seconds.
# A fleet server staggers image downloads -- roughly 1 TB over a 1 GbE link for
# a hundred machines -- so a client can legitimately wait hours for its slot.
# Bounded rather than infinite so a genuinely dead server still ends the install.
GHAF_QUEUE_MAX_WAIT="${GHAF_QUEUE_MAX_WAIT:-14400}"

# Wait until the server will actually serve the image, THEN return.
#
# Why this is separate from the download rather than curl's own --retry: the
# image is streamed straight into `bmaptool copy - <disk>`, so a retry that
# fires after curl has already emitted bytes restarts the response into the same
# pipe and corrupts the write. The transfer therefore has to be single-shot,
# which means every wait has to happen before it starts.
#
# The probe is a one-byte range request. It takes and immediately releases an
# admission slot, so it answers "would I be served now?" without consuming the
# transfer. Two clients can both see a free slot and race; that is harmless,
# because the cap is enforced on the real GET, not here.
wait_for_image_slot() {
  local url="$1" waited=0 code delay hdrs rc

  hdrs="$(mktemp)"
  # shellcheck disable=SC2064  # $hdrs must expand now, not at trap time
  trap "rm -f '$hdrs'" RETURN

  while :; do
    # One request, not two: headers to a file, status via -w, so the Retry-After
    # below describes the same answer the status came from.
    #
    # --max-filesize is load-bearing, not a safety belt. A server that does not
    # implement Range -- Python's SimpleHTTPRequestHandler is one -- ignores the
    # request and answers 200 with the WHOLE 10.5 GB body, so a probe without it
    # downloads the entire image just to ask a yes/no question. With a known
    # Content-Length curl refuses before transferring anything and still reports
    # the status, which is the answer we wanted.
    rc=0
    code="$(curl -sS -o /dev/null -D "$hdrs" -w '%{http_code}' \
      --connect-timeout 10 --max-filesize 1048576 -r 0-0 "$url" 2>/dev/null)" || rc=$?
    [ -n "$code" ] || code=000

    case "$code" in
    200 | 206)
      # 206 is a server that honoured the range; 200 with rc=63 is one that did
      # not and got stopped by --max-filesize. Both mean "you would be served".
      return 0
      ;;
    503) ;;
    000)
      # No HTTP answer at all: down or unreachable rather than busy. Still worth
      # retrying -- a restarting unit looks exactly like this -- but say which.
      echo "Install server not answering (curl exit ${rc}); retrying..." >&2
      ;;
    *)
      # 404, 403, 500: a real error the download would hit as well. Return and
      # let the download report it properly rather than masking it as a queue.
      return 0
      ;;
    esac

    delay="$(sed -n 's/^[Rr]etry-[Aa]fter:[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$hdrs" | head -1)"
    [ -n "$delay" ] || delay=15
    [ "$delay" -ge 1 ] 2>/dev/null || delay=15
    [ "$delay" -le 120 ] || delay=120

    if [ "$waited" -ge "$GHAF_QUEUE_MAX_WAIT" ]; then
      echo "Still queued after ${waited}s; giving up." >&2
      return 1
    fi

    # Printing this is the whole point: on a multi-hour fleet run, "queued" and
    # "wedged" look identical from the console otherwise.
    echo "Queued for the image (waited ${waited}s); retrying in ${delay}s..." >&2
    sleep "$delay"
    waited=$((waited + delay))
  done
}

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
set_boot_to_disk

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
