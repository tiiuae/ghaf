# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  givc-cli ? null,
  cliArgs ? "",
}:
let
  givc-cli-pkg =
    if givc-cli != null then
      givc-cli
    else
      writeShellApplication {
        name = "givc-cli";
        text = "exit 1";
      };
in
writeShellApplication {
  name = "wait-for-unit";

  runtimeInputs = [
    givc-cli-pkg
  ];

  text = builtins.replaceStrings [ "@GIVC_ARGS@" ] [ cliArgs ] (builtins.readFile ./wait-for-unit.sh);

  meta = {
    description = "Script to query a systemd unit status across VMs.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
