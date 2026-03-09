# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  coreutils,
  diffutils,
  gawk,
  gnugrep,
  gnused,
  systemd,
  util-linux,
}:
writeShellApplication {
  name = "fss-rootcause";
  runtimeInputs = [
    coreutils
    diffutils
    gawk
    gnugrep
    gnused
    systemd
    util-linux
  ];
  text = builtins.readFile ../../../modules/common/logging/fss-rootcause.sh;
}
