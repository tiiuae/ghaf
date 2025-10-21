# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  ...
}:
{
  config = {
    boot.extraModulePackages = [
      (pkgs.rtl8126.override { linuxPackages = config.boot.kernelPackages; })
    ];
  };
}
