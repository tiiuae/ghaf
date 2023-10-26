# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  # Waypipe with vsock and window borders
  waypipe = prev.waypipe.overrideAttrs (_prevAttrs: {
    src = final.pkgs.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "mstoeckl";
      repo = "waypipe";
      rev = "3efa3e56609cbab1ec3538eed1400b29fbb5249c";
      sha256 = "sha256-7+IbFSo71+VAB9+E5snY69eYweduEtFkBzKBt87KikQ=";
    };
    patches = [./waypipe-window-borders.patch];
  });
})
