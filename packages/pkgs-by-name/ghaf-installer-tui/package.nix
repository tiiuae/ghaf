# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  brightnessctl,
  coreutils,
  curl,
  e2fsprogs,
  efibootmgr,
  efitools,
  gawk,
  gnugrep,
  gnused,
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
    bmaptool
    brightnessctl # screen brightness on startup
    coreutils
    curl # fetch the image and its block map when netbooted
    e2fsprogs # chattr in efivar cleanup
    efibootmgr # the boot entry this installer leaves behind
    efitools # Secure Boot key enrollment
    gawk
    # installer-boot-lib.sh parses efibootmgr output with these. Masked until
    # now by the image's system PATH, which writeShellApplication only prepends to.
    gnugrep
    gnused
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
  + builtins.readFile ../../../lib/gum-lib.sh
  # Shared with ghaf-installer; both front-ends must decide the boot disk alike.
  + builtins.readFile ../../../lib/installer-boot-lib.sh
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
