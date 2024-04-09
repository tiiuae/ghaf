# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  kernelVersion = config.boot.kernelPackages.kernel.version;
  kernelMajor = lib.strings.toInt (lib.versions.major kernelVersion);
  kernelMinor = lib.strings.toInt (lib.versions.minor kernelVersion);
  kernelPatch = lib.strings.toInt (lib.versions.patch kernelVersion);
in {
  boot.kernelPatches = lib.optionals (kernelMajor == 6 && kernelMinor == 1 && kernelPatch >= 82) [
    # Fix MAC-address randomized on USB network cards because of kernel bug.
    # This specifically affects network cards used in testing.
    {
      patch = pkgs.fetchpatch2 {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net.git/patch/?id=2e91bb99b9d4f756e92e83c4453f894dda220f09";
        hash = "sha256-fX7yBsXW1oFt1Nfns42oZnCXf36qehXijvCNEmqBGsE=";
      };
    }
  ];
}
