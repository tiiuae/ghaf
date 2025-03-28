# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  ...
}:
{
  config = {
    boot.extraModulePackages = [ pkgs.rtl8126 ];
  };
}
