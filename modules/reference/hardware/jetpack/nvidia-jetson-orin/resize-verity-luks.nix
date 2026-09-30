# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  mapperName,
  keyDescription,
}:
pkgs.writeShellApplication {
  name = "resize-verity-luks";
  runtimeInputs = with pkgs; [
    coreutils
    cryptsetup
    gptfdisk
    parted
    util-linux
  ];
  text = ''
    real_dev=""
    while read -r field value _; do
      if [ "$field" = "device:" ]; then
        real_dev=$(readlink -f "$value")
        break
      fi
    done < <(cryptsetup status ${mapperName})
    [ -b "$real_dev" ] || { echo "ERROR: open LUKS backing device not found"; exit 1; }

    base_dev=$(basename "$real_dev")
    part_num=$(cat "/sys/class/block/$base_dev/partition")
    disk="/dev/$(basename "$(readlink -f "/sys/class/block/$base_dev/..")")"

    logical_sector_bytes=$(blockdev --getss "$disk")
    # Repair a displaced backup GPT and NVIDIA's reserved end sectors before
    # calculating APP's extent. A consistent table is only read.
    parted -s -f "$disk" print >/dev/null

    # Grow to the largest partition size that is an exact multiple of the
    # LUKS data-sector size.  A raw `resizepart 100%` can leave APP a few
    # 512-byte sectors too long on NVMe; cryptsetup then refuses to grow a
    # mapping whose data sector is 4096 bytes.
    part_start=$(( $(cat "/sys/class/block/$base_dev/start") * 512 / logical_sector_bytes ))
    last_usable=""
    while IFS= read -r line; do
      if [[ "$line" =~ last\ usable\ sector\ is\ ([0-9]+) ]]; then
        last_usable="''${BASH_REMATCH[1]}"
        break
      fi
    done < <(sgdisk -p "$disk")
    luks_sector_bytes=""
    while read -r field value _; do
      if [ "$field" = "sector:" ]; then
        luks_sector_bytes="$value"
        break
      fi
    done < <(cryptsetup luksDump "$real_dev")

    [[ "$part_start" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid APP start sector"; exit 1; }
    [[ "$last_usable" =~ ^[0-9]+$ ]] || { echo "ERROR: GPT last usable sector not found"; exit 1; }
    [[ "$logical_sector_bytes" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid disk sector size"; exit 1; }
    [[ "$luks_sector_bytes" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid LUKS sector size"; exit 1; }
    (( luks_sector_bytes >= logical_sector_bytes )) || { echo "ERROR: LUKS sector is smaller than disk sector"; exit 1; }
    (( luks_sector_bytes % logical_sector_bytes == 0 )) || { echo "ERROR: incompatible LUKS and disk sector sizes"; exit 1; }

    alignment=$((luks_sector_bytes / logical_sector_bytes))
    max_part_sectors=$((last_usable - part_start + 1))
    aligned_part_sectors=$((max_part_sectors / alignment * alignment))
    aligned_end=$((part_start + aligned_part_sectors - 1))
    (( aligned_part_sectors > 0 )) || { echo "ERROR: no usable aligned APP space"; exit 1; }

    aligned_kernel_sectors=$((aligned_part_sectors * logical_sector_bytes / 512))
    current_sectors=$(cat "/sys/class/block/$base_dev/size")
    (( current_sectors <= aligned_kernel_sectors )) || { echo "ERROR: refusing to shrink APP"; exit 1; }
    if (( current_sectors < aligned_kernel_sectors )); then
      echo "Growing APP partition $part_num on $disk..."
      parted -s -f -a none "$disk" unit s resizepart "$part_num" "''${aligned_end}s"
      udevadm settle
    fi

    # Do not race cryptsetup against the kernel's partition-table update.
    for _ in $(seq 1 50); do
      [ "$(cat "/sys/class/block/$base_dev/size")" -eq "$aligned_kernel_sectors" ] && break
      sleep 0.1
    done
    [ "$(cat "/sys/class/block/$base_dev/size")" -eq "$aligned_kernel_sectors" ] || {
      echo "ERROR: kernel did not observe the aligned APP size"
      exit 1
    }

    echo "Growing open LUKS mapping ${mapperName}..."
    cryptsetup resize \
      --key-description ${keyDescription} \
      ${mapperName}
  '';
}
