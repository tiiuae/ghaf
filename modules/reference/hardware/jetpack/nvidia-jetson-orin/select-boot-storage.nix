# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, luksUuid }:
pkgs.writeShellApplication {
  name = "select-boot-storage";
  runtimeInputs = with pkgs; [
    coreutils
    util-linux
    systemd
  ];
  text = ''
    efivar=''${1:-/sys/firmware/efi/efivars/LoaderDevicePartUUID-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f}
    uuid=$(tail -c +5 "$efivar" | tr -d '\000')
    [[ $uuid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || {
      echo "Boot loader did not identify a GPT ESP" >&2; exit 1;
    }
    uuid=''${uuid,,}
    for ((attempt=0; attempt<30; attempt++)); do
      mapfile -t esps < <(blkid -c /dev/null -t "PARTUUID=$uuid" -o device || true)
      (( ''${#esps[@]} )) && break
      sleep 1
    done
    [[ ''${#esps[@]} -eq 1 ]] || { echo "Boot ESP is missing or ambiguous" >&2; exit 1; }
    esp=''${esps[0]}
    [[ $(blkid -s TYPE -o value "$esp") == vfat ]] || { echo "Boot ESP is not FAT" >&2; exit 1; }
    esp_node=$(basename "$esp")
    disk=$(dirname "$(readlink -f "/sys/class/block/$esp_node")")
    roots=()
    for part in "$disk"/*/partition; do
      [[ -f "$part" ]] || continue
      node=$(basename "$(dirname "$part")")
      if [[ $(blkid -s TYPE -o value "/dev/$node") == crypto_LUKS && $(blkid -s UUID -o value "/dev/$node") == ${pkgs.lib.escapeShellArg luksUuid} ]]; then
        roots+=("$node")
      fi
    done
    [[ ''${#roots[@]} -eq 1 ]] || { echo "Boot disk must contain exactly one matching LUKS APP" >&2; exit 1; }
    root=''${roots[0]}
    mkdir -p /run/udev/rules.d
    printf 'SUBSYSTEM=="block", KERNEL=="%s", SYMLINK+="disk/ghaf-esp", TAG+="systemd"\nSUBSYSTEM=="block", KERNEL=="%s", SYMLINK+="disk/ghaf-root", TAG+="systemd"\n' \
      "$esp_node" "$root" > /run/udev/rules.d/99-ghaf-boot-storage.rules
    udevadm control --reload
    udevadm trigger --action=change "/sys/class/block/$esp_node" "/sys/class/block/$root"
    udevadm settle
    [[ $(readlink -f /dev/disk/ghaf-esp) == "$esp" && $(readlink -f /dev/disk/ghaf-root) == "/dev/$root" ]]
  '';
}
