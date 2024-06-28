# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  hostName,
  ...
}: {
  imports = [
    (import ./logs-source.nix {
      inherit pkgs config lib;
      hostName = "${hostName}";
    })
  ];
}
