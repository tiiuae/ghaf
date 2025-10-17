# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  coreutils,
  gawk,
  gnugrep,
  jq,
  pciutils,
  systemd,
}:
writeShellApplication {
  name = "pci-binder";
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    jq
    pciutils
    systemd
  ];
  text = builtins.readFile ./pci-binder.sh;
  meta = {
    description = "Script to unbind/rebind guest PCI device drivers";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
