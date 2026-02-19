# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.swap;
in
{
  options.ghaf.virtualization.microvm.swap = {
    enable = lib.mkEnableOption "zram compressed swap for VMs";
  };

  config = lib.mkIf cfg.enable {
    zramSwap = {
      enable = true;
      algorithm = "lzo-rle";
      memoryPercent = 25;
    };
    boot.kernel.sysctl."vm.swappiness" = 10;
  };
}
