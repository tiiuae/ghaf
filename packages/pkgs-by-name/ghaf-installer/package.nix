# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  coreutils,
  curl,
  e2fsprogs,
  efitools,
  gawk,
  hwinfo,
  lvm2,
  ncurses,
  parted,
  systemd,
  util-linux,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    bmaptool # sparse-aware copy + per-range sha256 verification
    coreutils
    curl # fetch the image and its block map when netbooted
    e2fsprogs # Needed for chattr in efivar cleanup
    efitools # Needed for Secure Boot key enrollment
    gawk # Needed for the awk in find_esp_device
    hwinfo
    lvm2 # Needed for vgchange, pvremove
    ncurses # Needed for `clear` command
    parted # Needed for partprobe
    systemd # Needed for udevadm settle
    util-linux
    zstd
  ];
  text = builtins.readFile ./ghaf-installer.sh;
  meta = {
    description = "Installer script for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
