# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  hwinfo,
  ncurses,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    hwinfo
    ncurses # Needed for `clear` command
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
