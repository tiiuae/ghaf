# shellcheck shell=bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Boot-entry, capacity and download-queue helpers, shared by ghaf-installer and
# ghaf-installer-tui. Prepended by each package, as lib/gum-lib.sh is.
#
# Disk and ESP are arguments: the two front-ends' find_esp_device disagree (the
# TUI's takes $1 and needs gum, the CLI's reads $DEVICE_NAME). Nothing here uses
# gum, `debug` or `run_spin` -- ghaf-installer has none of them.
#
# Every function is non-fatal: under the TUI's run_step a non-zero return would
# report a successful install as a failure.

# Refuse an image that cannot fit, before anything is written. The streaming dd
# fallback writes until end-of-device and leaves a disk whose GPT describes a
# larger one: unbootable, and not obviously wrong afterwards.
#
# Unknown sizes are not treated as failures -- an unmeasurable target (a file,
# a loop device in a test) is not evidence that the image is too big.
image_fits_device() {
  local image_size="$1" dev="$2" dev_size

  case "${image_size:-}" in
  '' | *[!0-9]*)
    echo "image size unknown; not checking capacity" >&2
    return 0
    ;;
  esac

  dev_size="$(blockdev --getsize64 "$dev" 2>/dev/null || true)"
  case "${dev_size:-}" in
  '' | *[!0-9]*)
    echo "cannot measure $dev; not checking capacity" >&2
    return 0
    ;;
  esac

  if [ "$image_size" -gt "$dev_size" ]; then
    echo "image needs $image_size bytes, $dev holds $dev_size" >&2
    return 1
  fi
}

# Reports rather than exits: Secure Boot enrollment cannot proceed without
# efivars, set_boot_to_disk only warns.
ensure_efivars() {
  [ -d /sys/firmware/efi/efivars ] || return 1
  mountpoint -q /sys/firmware/efi/efivars && return 0
  echo "Mounting efivarfs..." >&2
  mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null
}

# Read off the ESP, not assumed: disko writes it inside a VM, so the removable
# fallback may be all that is there. Echoes an EFI backslash path, or nothing.
find_esp_loader() {
  local esp_device="$1" mnt loader=""
  mnt="$(mktemp -d)"
  if ! mount -t vfat -o ro "$esp_device" "$mnt" 2>/dev/null; then
    rmdir "$mnt"
    return 1
  fi
  # systemd-boot first: the installed system manages that entry itself. The
  # fallback is the "any disk" path, so several disks could match the wrong one.
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

# Verify the entire executable x86/AArch64 UEFI boot chain against the db
# certificate that will be enrolled. This must run before enrollment: enrolling
# keys for an unsigned, differently signed, or Type-1 image can turn a successful
# install into an immediately unbootable machine once Secure Boot is enabled.
#
# Type-1 entries are deliberately rejected. They authenticate the kernel at
# best, while the initrd and editable command line remain separate unsigned
# inputs. Secure Ghaf images use Type-2 UKIs under EFI/Linux instead.
verify_secureboot_esp() {
  local esp_device="$1" keys_dir="$2" mnt loader uki
  local -a loaders=() ukis=()

  [ -s "$keys_dir/db.crt" ] || {
    echo "Missing Secure Boot verification certificate: $keys_dir/db.crt" >&2
    return 1
  }
  command -v sbverify >/dev/null 2>&1 || {
    echo "sbsigntool is not available in the installer environment." >&2
    return 1
  }

  mnt="$(mktemp -d)"
  if ! mount -t vfat -o ro "$esp_device" "$mnt" 2>/dev/null; then
    echo "Could not mount ESP $esp_device for Secure Boot verification." >&2
    rmdir "$mnt"
    return 1
  fi

  for loader in \
    "$mnt/EFI/systemd/systemd-bootx64.efi" \
    "$mnt/EFI/systemd/systemd-bootaa64.efi" \
    "$mnt/EFI/BOOT/BOOTX64.EFI" \
    "$mnt/EFI/BOOT/BOOTAA64.EFI"; do
    [ ! -f "$loader" ] || loaders+=("$loader")
  done
  if [ "${#loaders[@]}" -eq 0 ]; then
    echo "No supported EFI loader found on $esp_device." >&2
    umount "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    return 1
  fi

  while IFS= read -r -d '' uki; do
    ukis+=("$uki")
  done < <(find "$mnt/EFI/Linux" -maxdepth 1 -type f -iname '*.efi' -print0 2>/dev/null)
  if [ "${#ukis[@]}" -eq 0 ]; then
    echo "No Type-2 UKI found under EFI/Linux on $esp_device." >&2
    umount "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    return 1
  fi

  if find "$mnt/loader/entries" -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null | grep -q .; then
    echo "Type-1 boot entries remain on $esp_device; refusing Secure Boot enrollment." >&2
    umount "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    return 1
  fi

  for loader in "${loaders[@]}" "${ukis[@]}"; do
    if ! sbverify --cert "$keys_dir/db.crt" "$loader" >/dev/null 2>&1; then
      echo "EFI executable is not signed by $keys_dir/db.crt: ${loader#"$mnt/"}" >&2
      umount "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
      return 1
    fi
  done

  umount "$mnt" 2>/dev/null || {
    echo "Could not unmount ESP after Secure Boot verification." >&2
    return 1
  }
  rmdir "$mnt" 2>/dev/null || true
  echo "Verified Secure Boot loader and ${#ukis[@]} UKI(s) against $keys_dir/db.crt."
}

# efibootmgr's own error text is the whole story when the variable store is
# full, and every call here used to discard it into /dev/null -- which is why a
# machine that would not boot looked identical to one that did.
efibm() {
  local out rc=0
  out="$(efibootmgr "$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "efibootmgr $*: failed (rc=$rc): $out" >&2
  fi
  return "$rc"
}

# Dell firmware and the kernel both refuse variable writes as the store fills,
# and the failure is silent unless someone prints this.
nvram_usage() {
  df -k /sys/firmware/efi/efivars 2>/dev/null |
    awk 'NR == 2 { printf "%s of %s KiB used (%s)", $3, $2, $5 }' ||
    echo "unknown"
}

# Remove Ghaf entries whose ESP is gone. Reinstalling the same image reuses its
# entry; an image whose ESP lands a different PARTUUID strands the old one, and
# they accumulate and never expire. Measured: three on a Dell RA13250 over the
# B-slot work, on a machine that then booted into recovery.
#
# Keyed on "no partition with this PARTUUID exists", not "not the one we just
# wrote": a Ghaf install on a second disk is still bootable and must survive.
prune_stale_boot_entries() {
  local keep="$1" live entries stale bootnum uuid

  command -v efibootmgr >/dev/null 2>&1 || return 0

  live="$(lsblk -no PARTUUID 2>/dev/null | tr -d '[:blank:]' | tr '[:upper:]' '[:lower:]' | grep . || true)"
  # No readable partition table means every entry looks stale. Do nothing.
  [ -n "$live" ] || return 0

  entries="$(efibootmgr -v 2>/dev/null || true)"
  stale="$(
    printf '%s\n' "$entries" |
      sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\}[[:blank:]]*Ghaf[[:blank:]].*HD([0-9]*,GPT,\([0-9A-Fa-f-]\{1,\}\),.*/\1 \2/p' || true
  )"

  while read -r bootnum uuid; do
    [ -n "$bootnum" ] || continue
    [ "$bootnum" != "$keep" ] || continue
    printf '%s\n' "$live" | grep -qxF "$(printf '%s' "$uuid" | tr '[:upper:]' '[:lower:]')" && continue
    echo "Removing stale boot entry Boot$bootnum ($uuid)"
    efibm -b "$bootnum" -B ||
      echo "WARNING: could not remove Boot$bootnum; the store stays full." >&2
  done <<EOF
$stale
EOF
}

# Point the firmware at the disk just written. Before this, the only thing
# stopping a netbooted machine reinstalling in a loop was the server shutting
# down after one transfer, which a fleet server cannot do.
#
# -c creates the entry and puts it first in BootOrder (durable, works on a
# machine that never had a Linux entry); -n sets BootNext as a one-shot backstop
# for firmware that rewrites BootOrder.
set_boot_to_disk() {
  local device_name="$1" esp_device="$2"
  local part_num loader entries bootnum partuuid

  command -v efibootmgr >/dev/null 2>&1 || {
    echo "WARNING: efibootmgr not available; leaving boot order untouched." >&2
    return 0
  }

  ensure_efivars || {
    echo "WARNING: no EFI variables (legacy/CSM boot?); leaving boot order untouched." >&2
    return 0
  }

  echo "EFI variable store: $(nvram_usage)"

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

  # `|| true` on every pipeline: under `set -euo pipefail` a grep matching
  # nothing aborts the installer, and "no entry yet" is the normal case here.
  partuuid="$(lsblk -no PARTUUID "$esp_device" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)"

  # BEFORE creating anything, not after. The store is small and a full one makes
  # efibootmgr fail: on a Dell RA13250 at 64% used the create landed but the
  # deletes did not, leaving a machine that would not boot AND a stale entry
  # that made the next install worse. Deleting first is what keeps that from
  # compounding. The entry for the disk just written has a live PARTUUID, so
  # this cannot remove what we are about to reuse.
  prune_stale_boot_entries ""

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
      efibm -o "${order%,}" ||
        echo "WARNING: could not reorder BootOrder; BootNext below still applies." >&2
    fi
  else
    echo "Creating boot entry for $device_name partition $part_num"
    efibm -c -d "$device_name" -p "$part_num" -L "Ghaf" -l "$loader" || {
      echo "WARNING: could not create a boot entry; leaving boot order untouched." >&2
      echo "         EFI variable store: $(nvram_usage)" >&2
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
    efibm -n "$bootnum" &&
      echo "BootNext set to Boot$bootnum (one-shot)" ||
      echo "WARNING: could not set BootNext." >&2
  else
    echo "WARNING: could not determine the new boot entry number." >&2
  fi

  # Read back rather than trusting the writes: a store that refused one of them
  # leaves a machine that does not boot, and this is the only place it shows.
  if ! efibootmgr 2>/dev/null | grep -q "^Boot${bootnum}"; then
    echo "WARNING: Boot$bootnum is not in the store after writing it." >&2
  fi

  echo "EFI variable store after: $(nvram_usage)"

  # The only evidence anyone gets from an unattended fleet install.
  echo "--- efibootmgr ---"
  efibootmgr 2>/dev/null || true
  echo "------------------"
}

# How long to sit in an install server's queue before giving up, in seconds.
# A fleet server staggers image downloads -- roughly 1 TB over a 1 GbE link for
# a hundred machines -- so a client can legitimately wait hours for its slot.
# Bounded rather than infinite so a genuinely dead server still ends the install.
GHAF_QUEUE_MAX_WAIT="${GHAF_QUEUE_MAX_WAIT:-14400}"

# Wait until the server will serve the image, then return. Separate from the
# download because the transfer feeds `bmaptool copy - <disk>` single-shot: a
# curl --retry mid-stream restarts into the same pipe and corrupts the write.
#
# The probe is a one-byte range request, taking and releasing a slot. Two
# clients can race for it harmlessly -- the cap is enforced on the real GET.
wait_for_image_slot() {
  local url="$1" waited=0 code delay hdrs rc

  hdrs="$(mktemp)"
  # shellcheck disable=SC2064  # $hdrs must expand now, not at trap time
  trap "rm -f '$hdrs'" RETURN

  while :; do
    # One request, so Retry-After describes the status it came with.
    #
    # --max-filesize is load-bearing: a server that ignores Range answers 200
    # with the whole multi-GB body, and the probe would download the image to
    # ask a yes/no question. curl refuses on Content-Length and still reports.
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
