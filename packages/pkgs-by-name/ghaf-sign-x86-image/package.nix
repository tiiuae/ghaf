# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  jq,
  openssl,
  sbsigntool,
  systemd,
  util-linux,
  writeShellApplication,
  zstd,
}:
writeShellApplication {
  name = "ghaf-sign-x86-image";
  runtimeInputs = [
    bmaptool
    coreutils
    findutils
    gawk
    gnugrep
    jq
    openssl
    sbsigntool
    systemd
    util-linux
    zstd
  ];
  text = builtins.readFile ./ghaf-sign-x86-image.sh;
  meta.description = "Sign the EFI boot chain in a Ghaf x86 disk image outside the Nix store";
}
