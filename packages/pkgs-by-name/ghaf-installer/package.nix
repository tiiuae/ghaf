# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  coreutils,
  util-linux,
  hwinfo,
  ncurses,
  writeShellApplication,
  zstd,
  lvm2,
  parted,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    hwinfo
    ncurses # Needed for `clear` command
    lvm2 # Needed for vgchange, pvremove
    parted # Needed for partprobe
  ];
  text = builtins.readFile (
    lib.fileset.toSource {
      root = ./.;
      fileset = ./ghaf-installer.sh;
    }
    + "/ghaf-installer.sh"
  );
  meta = {
    description = "Installer script for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
