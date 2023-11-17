# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(_final: prev: {
  # TODO: Remove if this PR gets backported to nixos-23.05
  # https://github.com/NixOS/nixpkgs/pull/245228
  libjack2 = prev.libjack2.overrideAttrs (_old: {
    prePatch = ''
    '';
    postPatch = ''
      patchShebangs --build svnversion_regenerate.sh
    '';
  });
})
