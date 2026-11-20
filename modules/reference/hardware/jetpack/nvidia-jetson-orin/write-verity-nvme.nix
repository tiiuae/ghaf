# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
pkgs.writeShellApplication {
  name = "write-verity-nvme";
  runtimeInputs = with pkgs; [
    coreutils
    gnugrep
    gptfdisk
    util-linux
  ];
  text = ''
    disk=$1 esp=$2 app=$3
    test -b "$disk"
    test "$(blockdev --getss "$disk")" = 512
    if lsblk -nr -o MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
      echo "Refusing to overwrite a mounted disk: $disk" >&2
      exit 1
    fi
    esp_bytes=$(stat -c%s "$esp")
    app_bytes=$(stat -c%s "$app")
    (( esp_bytes > 0 && app_bytes > 0 && esp_bytes % 512 == 0 && app_bytes % 512 == 0 ))
    esp_start=2048
    app_start=$(( ((esp_start + esp_bytes / 512 + 2047) / 2048) * 2048 ))
    (( $(blockdev --getsize64 "$disk") >= (app_start + app_bytes / 512 + 2048) * 512 )) || {
      echo "The verity images do not fit on $disk" >&2
      exit 1
    }
    sgdisk --zap-all --clear \
      --new="1:$esp_start:+$((esp_bytes / 512))" --typecode=1:ef00 --change-name=1:esp \
      --new="2:$app_start:+$((app_bytes / 512))" --typecode=2:8300 --change-name=2:APP "$disk"
    dd if="$esp" of="$disk" bs=4M seek="$((esp_start * 512))" \
      iflag=fullblock oflag=direct,seek_bytes conv=notrunc,fsync status=progress
    dd if="$app" of="$disk" bs=4M seek="$((app_start * 512))" \
      iflag=fullblock oflag=direct,seek_bytes conv=notrunc,fsync status=progress
    blockdev --flushbufs "$disk"
  '';
}
