# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  waypipe-ssh = final.callPackage ../../../user-apps/waypipe-ssh {};

  # Waypipe with vsock and window borders
  waypipe = prev.waypipe.overrideAttrs (prevAttrs: {
    src = final.pkgs.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "mstoeckl";
      repo = "waypipe";
      rev = "ca4809435e781dfc6bd3006fde605860c8dcf179";
      sha256 = "sha256-tSLPlf7fVq8vwbr7fHotqM/sBSXYMDM1V5yth5bhi38=";
    };
    patches = [./waypipe-window-borders.patch];
  });
})
