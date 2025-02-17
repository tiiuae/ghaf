# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption;
in
{
  options.ghaf.disk.encryption = {
    enable = mkEnableOption "Ghaf disk encryption configuration";
  };
}
