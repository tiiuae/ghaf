# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellScriptBin,
  polkit,
  wireguard-gui,
  lib,
  ...
}:
writeShellScriptBin "wireguard-gui-launcher"
  ''
    PATH=/run/wrappers/bin:/run/current-system/sw/bin
    ${wireguard-gui}/bin/wireguard-gui
  ''
