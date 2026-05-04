# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  brightnessctl,
  coreutils,
  e2fsprogs,
  efitools,
  gawk,
  gum,
  lib,
  lvm2,
  ncurses,
  parted,
  pv,
  systemd,
  util-linux,
  writeShellApplication,
  writeTextFile,
  zstd,
}:
let
  installerLib = writeTextFile {
    name = "ghaf-installer-lib.sh";
    text = builtins.readFile ./ghaf-installer-lib.sh;
  };
in
writeShellApplication {
  name = "ghaf-installer-tui";
  runtimeInputs = [
    brightnessctl # screen brightness on startup
    coreutils
    e2fsprogs # chattr in efivar cleanup
    efitools # Secure Boot key enrollment
    gawk
    gum # TUI components
    lvm2 # vgchange, pvremove
    ncurses
    parted # partprobe
    pv
    systemd # udevadm
    util-linux
    zstd
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${installerLib}
  ''
  + builtins.readFile ./ghaf-installer-tui.sh;
  meta = {
    description = "Interactive TUI installer for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    license = lib.licenses.asl20;
  };
}
