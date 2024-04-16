# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Fix for ax88179_178a USB network card kernel driver MAC-address issue.
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.ax88179_178a;
in {
  options.ghaf.hardware.ax88179_178a = {
    enable = lib.mkEnableOption "fix for ax88179_178a USB network card kernel driver MAC-address";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPatches = [
      # Fix MAC-address randomized on USB network cards because of kernel bug.
      # This specifically affects network cards used in testing.
      {
        patch = pkgs.fetchpatch2 {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net.git/patch/?id=2e91bb99b9d4f756e92e83c4453f894dda220f09";
          hash = "sha256-fX7yBsXW1oFt1Nfns42oZnCXf36qehXijvCNEmqBGsE=";
        };
      }
    ];
  };
}
