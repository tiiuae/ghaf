# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  e2fsprogs,
  efitools,
  hwinfo,
  lvm2,
  ncurses,
  parted,
  util-linux,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    e2fsprogs # Needed for chattr in efivar cleanup
    efitools # Needed for Secure Boot key enrollment
    hwinfo
    lvm2 # Needed for vgchange, pvremove
    ncurses # Needed for `clear` command
    parted # Needed for partprobe
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
