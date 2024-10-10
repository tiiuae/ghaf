# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#
{
  writeShellApplication,
  util-linux,
  fprintd,
}:
writeShellApplication {
  name = "finger-print-enroll";
  runtimeInputs = [
    util-linux
    fprintd
  ];
  text = builtins.readFile ./enroll.sh;
  meta = {
    description = "Helper script for finger print enrollment";
    platforms = [
      "x86_64-linux"
    ];
  };
}
