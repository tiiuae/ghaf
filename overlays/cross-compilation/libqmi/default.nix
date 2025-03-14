# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# papirus-icon-theme cross-compilation fixes (removing qt dependency)
#
# TODO: check if we should be using the qt6 version of the theme
# kdePackages.breeze-icons and not the deprecated qt5 version
{ final, prev }:
prev.libqmi.override {
  meson = prev.buildPackages.meson.overrideAttrs {
    src = final.fetchFromGitHub {
      owner = "mesonbuild";
      repo = "meson";
      tag = "1.6.1";
      hash = "sha256-t0JItqEbf2YqZnu5mVsCO9YGzB7WlCfsIwi76nHJ/WI=";
    };
  };
}
