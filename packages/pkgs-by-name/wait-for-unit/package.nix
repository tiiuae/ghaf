# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  grpcurl,
  jq,
}:
writeShellApplication {
  name = "wait-for-unit";

  runtimeInputs = [
    grpcurl
    jq
  ];

  text = builtins.readFile ./wait-for-unit.sh;

  meta = {
    description = "Script to query a systemd unit status across VMs.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
